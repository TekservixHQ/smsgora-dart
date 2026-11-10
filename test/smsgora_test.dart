import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smsgora/smsgora.dart';
import 'package:test/test.dart';

void main() {
  late http.Request last;
  var status = 200;
  var reply = '{"success":true,"data":{"message_ids":[1873]}}';
  var headers = <String, String>{'content-type': 'application/json'};

  SmsGora client() => SmsGora('sgk_test', baseUrl: 'https://example.test/api/',
          httpClient: MockClient((req) async {
        last = req;
        return http.Response(reply, status, headers: headers);
      }));

  Map<String, dynamic> body() => jsonDecode(last.body) as Map<String, dynamic>;

  setUp(() {
    status = 200;
    reply = '{"success":true,"data":{"message_ids":[1873]}}';
    headers = {'content-type': 'application/json'};
  });

  test('sendSms', () async {
    final res = await client().sendSms(to: ['+15551234567'], message: 'Hi');
    expect(res['message_ids'], [1873]);
    expect(last.method, 'POST');
    expect(last.url.toString(), 'https://example.test/api/send-sms');
    expect(last.headers['x-api-key'], 'sgk_test');
    expect(body(), {
      'recipients': ['+15551234567'],
      'message': 'Hi'
    });
  });

  test('device, SIM and schedule', () async {
    await client().sendSms(
        to: ['+1', '+2'],
        message: 'x',
        deviceId: 42,
        simSlot: 1,
        scheduleAt: DateTime.utc(2026, 12, 1, 8));
    expect(last.url.path, '/api/devices/42/send-sms');
    expect(body()['sim_slot'], 1);
    expect(body()['schedule_at'], '2026-12-01T08:00:00Z');
  });

  test('bulk and other paths', () async {
    final c = client();
    await c.sendBulkSms(
        42,
        [
          const BulkMessage(['+1'], message: 'a'),
          const BulkMessage(['+2'])
        ],
        messageTemplate: 't');
    expect(last.url.path, '/api/devices/42/send-bulk-sms');
    expect(body()['messageTemplate'], 't');
    expect((body()['messages'] as List)[1], {
      'recipients': ['+2']
    });

    await c.listReceivedSms(filters: {'phone': '+1555', 'since': '2026-11-01'});
    expect(last.url.toString(),
        'https://example.test/api/received-sms?phone=%2B1555&since=2026-11-01');
    await c.listReceivedSms(deviceId: 3);
    expect(last.url.path, '/api/devices/3/get-received-sms');
    await c.cancelMessage(7);
    expect(last.url.path, '/api/messages/7/cancel');
    await c.createWebhook('https://my.app/hook');
    expect(body()['events'], ['sms.received']);
    await c.deleteWebhook(9);
    expect(last.method, 'DELETE');
    expect(() => c.sendSms(to: [], message: 'x'), throwsArgumentError);
  });

  test('API errors', () async {
    status = 429;
    reply =
        '{"success":false,"message":"Too many requests","errors":{"recipients":["bad"]}}';
    headers = {'content-type': 'application/json', 'retry-after': '12'};
    try {
      await client().getAccount();
      fail('expected error');
    } on SmsGoraException catch (e) {
      expect(e.status, 429);
      expect(e.message, 'Too many requests');
      expect(e.retryAfter, 12);
      expect((e.errors as Map)['recipients'], ['bad']);
    }

    status = 502;
    reply = '<html>bad gateway</html>';
    try {
      await client().listDevices();
      fail('expected error');
    } on SmsGoraException catch (e) {
      expect(e.message, 'HTTP 502');
      expect(e.body, '<html>bad gateway</html>');
    }
  });

  test('verifyWebhook', () {
    final raw =
        utf8.encode('{"event":"sms.received","data":{"from":"+15551234567"}}');
    const sig =
        'sha256=e125c07dfbecb498e8979383d7b9f0815efb128755409794b486d4bbb7199583';
    expect(SmsGora.verifyWebhook(raw, sig, 'whsec_test'), isTrue);
    expect(SmsGora.verifyWebhook(raw, sig, 'other'), isFalse);
    expect(
        SmsGora.verifyWebhook(utf8.encode('{}'), sig, 'whsec_test'), isFalse);
    expect(SmsGora.verifyWebhook(raw, null, 'whsec_test'), isFalse);
  });

  test('requires an API key', () {
    expect(() => SmsGora(''), throwsArgumentError);
  });
}
