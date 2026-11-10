import 'dart:io';

import 'package:smsgora/smsgora.dart';

Future<void> main() async {
  // Create an API key in SMS Gora -> API keys. Keep it on your server.
  final sms = SmsGora(Platform.environment['SMSGORA_KEY']!);

  try {
    final result = await sms.sendSms(
      to: ['+15551234567'],
      message: 'Your verification code is 482913',
    );
    print('Queued: ${result['message_ids']}');

    final status = await sms.getMessage(result['message_ids'][0] as int);
    print('Status: ${status['status']}');
  } on SmsGoraException catch (e) {
    print('SMS Gora error ${e.status}: ${e.message}');
  } finally {
    sms.close();
  }
}
