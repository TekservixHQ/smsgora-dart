/// Dart and Flutter client for the SMS Gora SMS Gateway API.
///
/// SMS Gora turns Android phones with ordinary SIM cards into an SMS gateway:
/// your server calls the API, a linked phone sends the text, and replies and
/// delivery reports come back to you.
///
/// ```dart
/// final sms = SmsGora(Platform.environment['SMSGORA_KEY']!);
/// final result = await sms.sendSms(to: ['+15551234567'], message: 'Your code is 482913');
/// print(result['message_ids']); // [1873]
/// ```
///
/// Keep the API key on your server. API reference: https://tekservix.com/smsgora/docs/
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// Package version, sent in the User-Agent header.
const String smsGoraVersion = '1.0.1';

/// Thrown when the API answers with an error.
class SmsGoraException implements Exception {
  /// HTTP status.
  final int status;

  /// Message from the API, or `HTTP <status>`.
  final String message;

  /// Field errors, when the API sends them.
  final Object? errors;

  /// Parsed JSON body, or the raw text when it was not JSON.
  final Object? body;

  /// Seconds to wait before retrying (sent with 429).
  final double? retryAfter;

  /// Creates an API error.
  SmsGoraException(this.status, this.message,
      {this.errors, this.body, this.retryAfter});

  @override
  String toString() => 'SmsGoraException: $message (HTTP $status)';
}

/// One entry for [SmsGora.sendBulkSms]. Leave [message] null to use the shared template.
class BulkMessage {
  /// Numbers for this entry.
  final List<String> recipients;

  /// Own text for these numbers.
  final String? message;

  /// Creates a bulk entry.
  const BulkMessage(this.recipients, {this.message});

  Map<String, Object> _toJson() =>
      {'recipients': recipients, if (message != null) 'message': message!};
}

/// SMS Gora API client. Reuse one instance; call [close] when done.
class SmsGora {
  /// Production API base URL.
  static const String defaultBaseUrl = 'https://tekservix.com/smsgora/api/v1';

  /// Base URL in use.
  final String baseUrl;

  final String _apiKey;
  final Duration _timeout;
  final http.Client _http;
  final bool _ownsClient;

  /// Client with your API key (starts with `sgk_`, from SMS Gora -> API keys).
  ///
  /// Pass [httpClient] to reuse your own client (proxy, retries, tests).
  SmsGora(String apiKey,
      {String baseUrl = defaultBaseUrl,
      Duration timeout = const Duration(seconds: 30),
      http.Client? httpClient})
      : _apiKey = apiKey,
        baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
        _timeout = timeout,
        _http = httpClient ?? http.Client(),
        _ownsClient = httpClient == null {
    if (apiKey.isEmpty) {
      throw ArgumentError.value(apiKey, 'apiKey',
          'SmsGora: apiKey is required (create one in SMS Gora -> API keys)');
    }
  }

  /// Call any documented endpoint, e.g. `request('GET', '/devices')`.
  /// Returns the decoded `data` field.
  Future<dynamic> request(String method, String path, {Object? body}) async {
    final req = http.Request(method.toUpperCase(), Uri.parse('$baseUrl$path'))
      ..headers['x-api-key'] = _apiKey
      ..headers['Accept'] = 'application/json'
      ..headers['User-Agent'] = 'smsgora-dart/$smsGoraVersion';
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }

    final res =
        await http.Response.fromStream(await _http.send(req).timeout(_timeout));
    final text = utf8.decode(res.bodyBytes, allowMalformed: true);
    Object? json;
    if (text.isNotEmpty) {
      try {
        json = jsonDecode(text);
      } on FormatException {
        json = null;
      }
    }

    final map = json is Map ? json : null;
    if (res.statusCode >= 400 || map?['success'] == false) {
      final retry = res.headers['retry-after'];
      throw SmsGoraException(
        res.statusCode,
        map?['message'] is String
            ? map!['message'] as String
            : 'HTTP ${res.statusCode}',
        errors: map?['errors'],
        body: json ?? text,
        retryAfter: retry == null ? null : double.tryParse(retry.trim()),
      );
    }
    if (map != null && map.containsKey('data')) return map['data'];
    return json;
  }

  /// Send an SMS to up to 1,000 numbers. Uses your best online phone unless
  /// [deviceId] is given. [simSlot]: 0 = SIM 1, 1 = SIM 2.
  /// Returns `{"message_ids": [...]}`.
  Future<dynamic> sendSms(
      {required List<String> to,
      required String message,
      int? deviceId,
      int? simSlot,
      DateTime? scheduleAt}) {
    if (to.isEmpty) {
      throw ArgumentError.value(
          to, 'to', 'sendSms: at least one recipient is required');
    }
    final path = deviceId == null ? '/send-sms' : '/devices/$deviceId/send-sms';
    return request('POST', path, body: {
      'recipients': to,
      'message': message,
      if (simSlot != null) 'sim_slot': simSlot,
      if (scheduleAt != null) 'schedule_at': _iso(scheduleAt),
    });
  }

  /// Different texts for different people in one call (up to 5,000 recipients).
  Future<dynamic> sendBulkSms(int deviceId, List<BulkMessage> messages,
      {String? messageTemplate}) {
    return request('POST', '/devices/$deviceId/send-bulk-sms', body: {
      'messages': messages.map((m) => m._toJson()).toList(),
      if (messageTemplate != null) 'messageTemplate': messageTemplate,
    });
  }

  /// Status is queued, dispatched, sent, delivered, failed or cancelled.
  Future<dynamic> getMessage(int id) => request('GET', '/messages/$id');

  /// Cancel a queued or scheduled message.
  Future<dynamic> cancelMessage(int id) =>
      request('POST', '/messages/$id/cancel');

  /// Filters: direction (in/out), status, device_id, phone, since, after_id, page, limit.
  Future<dynamic> listMessages([Map<String, Object?> filters = const {}]) =>
      request('GET', '/messages${_query(filters)}');

  /// Incoming SMS for all phones, or one phone with [deviceId].
  Future<dynamic> listReceivedSms(
      {int? deviceId, Map<String, Object?> filters = const {}}) {
    final path = deviceId == null
        ? '/received-sms'
        : '/devices/$deviceId/get-received-sms';
    return request('GET', '$path${_query(filters)}');
  }

  /// One bulk batch.
  Future<dynamic> getBatch(int id) => request('GET', '/batches/$id');

  /// Your linked Android phones.
  Future<dynamic> listDevices() => request('GET', '/devices');

  /// One phone.
  Future<dynamic> getDevice(int id) => request('GET', '/devices/$id');

  /// Account, plan and usage.
  Future<dynamic> getAccount() => request('GET', '/account');

  /// Your webhooks.
  Future<dynamic> listWebhooks() => request('GET', '/webhooks');

  /// Register a webhook. The answer includes the secret (returned only once).
  Future<dynamic> createWebhook(String url,
          {List<String> events = const ['sms.received'], int? deviceId}) =>
      request('POST', '/webhooks',
          body: {'url': url, 'events': events, 'device_id': deviceId});

  /// Delete a webhook.
  Future<dynamic> deleteWebhook(int id) => request('DELETE', '/webhooks/$id');

  /// Close the underlying HTTP client (only if this instance created it).
  void close() {
    if (_ownsClient) _http.close();
  }

  /// Check the `X-SmsGora-Signature` header (`sha256=<hex HMAC-SHA256 of the raw body>`).
  /// Pass the raw request body exactly as received, before JSON parsing.
  static bool verifyWebhook(
      List<int> rawBody, String? signature, String secret) {
    if (rawBody.isEmpty ||
        signature == null ||
        signature.isEmpty ||
        secret.isEmpty) {
      return false;
    }
    final mac = Hmac(sha256, utf8.encode(secret)).convert(rawBody);
    return _constantTimeEquals(
        utf8.encode('sha256=$mac'), utf8.encode(signature));
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  static String _iso(DateTime t) {
    final s = t.toUtc().toIso8601String();
    // 2026-12-01T08:00:00.000Z -> 2026-12-01T08:00:00Z
    return s.replaceFirst(RegExp(r'\.\d+Z$'), 'Z');
  }

  static String _query(Map<String, Object?> params) {
    final pairs = params.entries
        .where((e) => e.value != null && '${e.value}'.isNotEmpty)
        .map((e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent('${e.value}')}')
        .toList();
    return pairs.isEmpty ? '' : '?${pairs.join('&')}';
  }
}
