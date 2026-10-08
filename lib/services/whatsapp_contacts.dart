import 'dart:io';

import 'package:flutter/services.dart';

enum WhatsAppContact {
  owner('573052330643'),
  coOwner('573115788917');

  const WhatsAppContact(this.phone);

  final String phone;

  Uri link() => Uri.https('wa.me', '/$phone', {
    'text': 'Hola, necesito ayuda con BRUGES FINANZAS 360.',
  });
}

class WhatsAppContacts {
  WhatsAppContacts._();

  static const _channel = MethodChannel('com.bruges.finanzas360/external');

  static WhatsAppContact get owner => WhatsAppContact.owner;
  static WhatsAppContact get coOwner => WhatsAppContact.coOwner;

  static Future<bool> open(WhatsAppContact contact) async {
    final uri = contact.link();
    if (Platform.isAndroid) {
      return await _channel.invokeMethod<bool>('openUrl', uri.toString()) ??
          false;
    }
    if (Platform.isWindows) {
      await Process.start('rundll32.exe', [
        'url.dll,FileProtocolHandler',
        uri.toString(),
      ], mode: ProcessStartMode.detached);
      return true;
    }
    return false;
  }
}
