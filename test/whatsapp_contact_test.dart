import 'package:flutter_test/flutter_test.dart';
import 'package:bruges_finanzas_360/services/whatsapp_contacts.dart';

void main() {
  test(
    'owner WhatsApp link opens the owner contact with the support message',
    () {
      final link = WhatsAppContacts.owner.link();
      expect(link.host, 'wa.me');
      expect(link.path, '/573052330643');
      expect(link.queryParameters['text'], contains('BRUGES FINANZAS 360'));
    },
  );

  test('co-owner WhatsApp link uses the co-owner contact', () {
    final link = WhatsAppContacts.coOwner.link();
    expect(link.host, 'wa.me');
    expect(link.path, '/573115788917');
  });
}
