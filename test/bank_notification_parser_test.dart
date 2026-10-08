import 'package:flutter_test/flutter_test.dart';
import 'package:bruges_finanzas_360/domain/money_movement.dart';
import 'package:bruges_finanzas_360/services/bank_notification_parser.dart';

void main() {
  final parser = BankNotificationParser();

  test('registers verified Android package IDs for Colombian wallets', () {
    expect(
      bankNotificationPackages.keys,
      containsAll(<String>[
        'com.nequi.MobileApp',
        'co.com.bancolombia.personas.superapp',
        'com.davivienda.daviplataapp',
        'com.avalsolucionesdigitalessa.dale_app_embedded',
        'com.movilred.subscriber',
      ]),
    );
  });

  test(
    'converts an allowlisted income notification into a review suggestion',
    () {
      final observation = parser.parse(
        packageName: 'com.nequi.MobileApp',
        notificationKey: 'nequi-key-1',
        title: 'Plata recibida',
        text: r'Recibiste $ 25.000 de Andrea. Ref: ABC12345',
        observedAt: DateTime.utc(2026, 10, 8, 12),
      );

      expect(observation, isNotNull);
      expect(observation!.source, 'Nequi');
      expect(observation.kind, MovementKind.income);
      expect(observation.amountMinor, 25000);
      expect(observation.currency, 'COP');
      expect(observation.reviewState, 'review');
      expect(observation.id, contains('nequi-key-1'));
      final movement = observation.toMovement();
      expect(movement.id, observation.id);
      expect(movement.amountMinor, 25000);
      expect(movement.category, 'Transferencia detectada · Nequi');
      expect(movement.origin, MovementOrigin.notification);
      expect(movement.verification, MovementVerification.unverified);
      expect(movement.sourceName, 'Nequi');
      expect(movement.counterparty, 'Andrea');
      expect(movement.reference, 'ABC12345');
      expect(movement.note, contains('no es confirmación bancaria'));
    },
  );

  test(
    'ignores unrelated packages and queues ambiguous transfers for review',
    () {
      expect(
        parser.parse(
          packageName: 'com.example.chat',
          notificationKey: 'chat-1',
          title: 'Transferencia recibida',
          text: r'Recibiste $ 25.000',
          observedAt: DateTime.utc(2026),
        ),
        isNull,
      );
      final ambiguous = parser.parse(
        packageName: 'co.com.bancolombia.personas.superapp',
        notificationKey: 'bank-1',
        title: 'Movimiento',
        text: r'Pagaste $ 25.000 y recibiste $ 30.000',
        observedAt: DateTime.utc(2026),
      );
      expect(ambiguous, isNotNull);
      expect(ambiguous!.isReadyForAutomaticRegistration, isFalse);
      expect(ambiguous.kind, isNull);
      expect(ambiguous.reviewReason, 'Tipo de movimiento ambiguo');
    },
  );

  test('parses a notification from another registered wallet', () {
    final observation = parser.parse(
      packageName: 'com.davivienda.daviplataapp',
      notificationKey: 'daviplata-key',
      title: 'Transferencia enviada',
      text: r'Enviaste $ 8.500 a Carlos Pérez. Ref: 778899',
      observedAt: DateTime.utc(2026, 10, 8, 14, 15),
    );

    expect(observation, isNotNull);
    expect(observation!.source, 'DaviPlata');
    expect(observation.kind, MovementKind.expense);
    expect(observation.amountMinor, 8500);
    expect(observation.counterparty, 'Carlos Pérez');
    expect(observation.reference, '778899');
  });

  test('reads the sanitized millisecond payload queued by Android', () {
    final observation = BankNotificationObservation.fromJson({
      'id': 'bank:hashed-id',
      'source': 'Nequi',
      'packageName': 'com.nequi.MobileApp',
      'kind': 'income',
      'amountMinor': 25000,
      'currency': 'COP',
      'observedAt': DateTime.utc(2026, 10, 8, 12).millisecondsSinceEpoch,
      'counterparty': 'Andrea',
      'reference': 'ABC12345',
      'method': null,
      'reportedStatus': 'completed_reported',
      'reviewReason': null,
    });

    expect(observation.isReadyForAutomaticRegistration, isTrue);
    expect(observation.observedAt, DateTime.utc(2026, 10, 8, 12));
    expect(observation.toMovement().origin, MovementOrigin.notification);
    expect(
      observation.toMovement().verification,
      MovementVerification.unverified,
    );
  });
}
