import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bruges_finanzas_360/data/bank_observation_repository.dart';
import 'package:bruges_finanzas_360/domain/money_movement.dart';
import 'package:bruges_finanzas_360/services/bank_notification_parser.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('bruges-observations-');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test(
    'persists deduplicated suggestions as review-only until decided',
    () async {
      final repository = await BankObservationRepository.open(directory);
      final observation = BankNotificationParser().parse(
        packageName: 'com.nequi.MobileApp',
        notificationKey: 'notification-9',
        title: 'Plata recibida',
        text: r'Recibiste $ 25.000',
        observedAt: DateTime.utc(2026, 10, 8),
      )!;

      expect(await repository.add(observation), isTrue);
      expect(await repository.add(observation), isFalse);
      final saved = await repository.listPending();
      expect(saved, hasLength(1));
      expect(saved.single.reviewState, 'review');
      expect(saved.single.kind, MovementKind.income);

      await repository.markReviewed(observation.id, accepted: false);
      expect(await repository.listPending(), isEmpty);
    },
  );

  test('serializes concurrent duplicate notifications', () async {
    final repository = await BankObservationRepository.open(directory);
    final observation = BankNotificationParser().parse(
      packageName: 'com.nequi.MobileApp',
      notificationKey: 'same-notification',
      title: 'Transferencia enviada',
      text: r'Enviaste $ 9.000',
      observedAt: DateTime.utc(2026, 10, 8),
    )!;

    final results = await Future.wait([
      repository.add(observation),
      repository.add(observation),
    ]);

    expect(results.where((result) => result).length, 1);
    expect(await repository.listPending(), hasLength(1));
  });
}
