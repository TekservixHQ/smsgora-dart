# smsgora

[![pub package](https://img.shields.io/pub/v/smsgora.svg)](https://pub.dev/packages/smsgora)
[![tests](https://github.com/TekservixHQ/smsgora-dart/actions/workflows/tests.yml/badge.svg)](https://github.com/TekservixHQ/smsgora-dart/actions/workflows/tests.yml)

Dart and Flutter client for the [SMS Gora SMS Gateway](https://tekservix.com/smsgora/) API.

SMS Gora turns Android phones with ordinary SIM cards into an SMS gateway. Your server calls the API, a linked phone sends the text, and replies and delivery reports come back to you. There's no sender ID registration and no per-message fee from us: your mobile operator bills the texts like any SMS.

- Dart backends (Dart Frog, Shelf, Serverpod, Cloud Functions) and Dart CLI tools
- Only depends on `http` and `crypto`
- Webhook signature check built in

## Install

```bash
dart pub add smsgora
```

## Quick start

Create an API key in the SMS Gora dashboard (SMS Gora -> API keys) and keep it on your server.

```dart
import 'dart:io';

import 'package:smsgora/smsgora.dart';

Future<void> main() async {
  final sms = SmsGora(Platform.environment['SMSGORA_KEY']!);

  final result = await sms.sendSms(
    to: ['+15551234567'],
    message: 'Your verification code is 482913',
  );
  print(result['message_ids']); // [1873]

  sms.close();
}
```

### Flutter apps

**Don't put the API key inside a Flutter app.** Anyone can pull it out of the APK or IPA and send SMS from your account. Have the app call your own backend (Dart Frog, Firebase Cloud Functions, any server), and let the backend use this package.

## Sending

```dart
// Several recipients (up to 1,000 per call)
await sms.sendSms(to: ['+15551234567', '+447700900123'], message: 'Your order has shipped');

// From a chosen phone and SIM, scheduled for later
await sms.sendSms(
  to: ['+15551234567'],
  message: 'Reminder: your appointment is tomorrow at 10:00',
  deviceId: 42,
  simSlot: 1, // 0 = SIM 1, 1 = SIM 2
  scheduleAt: DateTime.utc(2026, 12, 1, 8),
);

// Different texts for different people in one call (up to 5,000 recipients)
await sms.sendBulkSms(42, [
  BulkMessage(['+15551234567'], message: 'Hi Aline, parcel #1042 is ready.'),
  BulkMessage(['+15557654321']),
], messageTemplate: 'Hello, your parcel is ready for pickup.');
```

## Delivery status and incoming SMS

```dart
final msg = await sms.getMessage(1873);
print(msg['status']); // queued -> dispatched -> sent -> delivered (or failed)

await sms.cancelMessage(1874); // works while queued or scheduled

final inbox = await sms.listReceivedSms(filters: {'since': '2026-11-01', 'limit': 50});
final phones = await sms.listDevices();
final account = await sms.getAccount();
```

Anything else in the [API reference](https://tekservix.com/smsgora/docs/) is one call away:

```dart
final batch = await sms.request('GET', '/batches/311');
```

## Webhooks

Add your HTTPS URL in SMS Gora -> Webhooks (or with `createWebhook`) and keep the secret. Each request carries `X-SmsGora-Signature: sha256=...`, an HMAC-SHA256 of the raw body. Shelf example:

```dart
Future<Response> smsWebhook(Request request) async {
  final raw = await request.read().expand((chunk) => chunk).toList();
  final ok = SmsGora.verifyWebhook(
    raw,
    request.headers['x-smsgora-signature'],
    Platform.environment['SMSGORA_WEBHOOK_SECRET']!,
  );
  if (!ok) return Response.unauthorized('bad signature');

  final event = jsonDecode(utf8.decode(raw));
  if (event['event'] == 'sms.received') {
    // event['data']['from'], event['data']['message']: queue slow work
  }
  return Response.ok('ok'); // answer within 10 seconds
}
```

## Errors

Failed calls throw `SmsGoraException` with `status`, `message`, field `errors` and, on 429, `retryAfter` in seconds.

```dart
try {
  await sms.sendSms(to: ['+15551234567'], message: 'Hi');
} on SmsGoraException catch (e) {
  if (e.status == 429) {
    // 300 requests/minute per key, or plan limit
    await Future.delayed(Duration(seconds: (e.retryAfter ?? 5).ceil()));
  }
}
```

## Migrating from TextBee

SMS Gora accepts TextBee-style requests, so most integrations switch by changing the base URL and key. See the [compatibility notes](https://tekservix.com/smsgora/docs/).

## More from Tekservix

- [WAservix WhatsApp API Gateway](https://tekservix.com/waservix/): send WhatsApp messages from your own number (`dart pub add waservix`)
- [AI Sales Agent](https://tekservix.com/ai-sales-agent): answers customers on WhatsApp and SMS using your website's content
- [Website to App](https://tekservix.com/mobile-apps): turn your website into Android and iOS apps
- SMS Gora is also available for Node.js, Python, PHP, Go, Java/Kotlin, .NET, Ruby, Swift and Rust: see [github.com/TekservixHQ](https://github.com/TekservixHQ)

## License

MIT
