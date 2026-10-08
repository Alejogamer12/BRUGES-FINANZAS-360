import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:bruges_finanzas_360/data/movement_repository.dart';
import 'package:bruges_finanzas_360/domain/money_movement.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('bruges-ledger-');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test(
    'persists movements across repository restarts without duplicate IDs',
    () async {
      final firstRepository = await MovementRepository.open(directory);
      final movement = MoneyMovement(
        id: 'movement-1',
        kind: MovementKind.expense,
        amountMinor: 25000,
        category: 'Mercado',
        createdAt: DateTime.utc(2026, 10, 8, 16, 30),
        note: 'Compra semanal',
      );

      expect(await firstRepository.addMovement(movement), isTrue);
      expect(await firstRepository.addMovement(movement), isFalse);

      final restartedRepository = await MovementRepository.open(directory);
      final saved = await restartedRepository.listMovements();
      expect(saved, hasLength(1));
      expect(saved.single.id, 'movement-1');
      expect(saved.single.amountMinor, 25000);
      expect(saved.single.category, 'Mercado');
      expect(saved.single.note, 'Compra semanal');
      expect(saved.single.syncState, MovementSyncState.pending);
    },
  );

  test(
    'persists detected source and unverified status without losing fields',
    () async {
      final repository = await MovementRepository.open(directory);
      final movement = MoneyMovement(
        id: 'notification-1',
        kind: MovementKind.expense,
        amountMinor: 8500,
        category: 'Transferencia detectada · DaviPlata',
        sourceName: 'DaviPlata',
        counterparty: 'Carlos Pérez',
        reference: '778899',
        origin: MovementOrigin.notification,
        verification: MovementVerification.unverified,
        createdAt: DateTime.utc(2026, 10, 8, 14, 15),
      );

      await repository.addMovement(movement);
      final reopened = await MovementRepository.open(directory);
      final saved = (await reopened.listMovements()).single;

      expect(saved.origin, MovementOrigin.notification);
      expect(saved.verification, MovementVerification.unverified);
      expect(saved.sourceName, 'DaviPlata');
      expect(saved.counterparty, 'Carlos Pérez');
      expect(saved.reference, '778899');
    },
  );

  test('migrates a version 1 file without changing its movements', () async {
    final file = File(
      '${directory.path}${Platform.pathSeparator}movements.json',
    );
    await directory.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'version': 1,
        'movements': [
          {
            'id': 'legacy-1',
            'kind': 'expense',
            'amountMinor': 9800,
            'category': 'Transporte',
            'note': 'Registro anterior',
            'createdAt': '2026-10-07T12:00:00.000Z',
            'syncState': 'pending',
          },
        ],
      }),
    );

    final repository = await MovementRepository.open(directory);
    final saved = await repository.listMovements();
    final persisted =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;

    expect(persisted['version'], 3);
    expect(saved, hasLength(1));
    expect(saved.single.id, 'legacy-1');
    expect(saved.single.amountMinor, 9800);
    expect(saved.single.currency, 'COP');
    expect(saved.single.note, 'Registro anterior');
  });

  test(
    'migrates release version 2 without losing notification metadata',
    () async {
      final file = File(
        '${directory.path}${Platform.pathSeparator}movements.json',
      );
      await directory.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          'version': 2,
          'movements': [
            {
              'id': 'old-detected',
              'kind': 'income',
              'amountMinor': 125000,
              'currency': 'COP',
              'category': 'Transferencia detectada · Nequi',
              'note': 'Aviso reportado',
              'createdAt': '2026-10-08T10:30:00.000Z',
              'syncState': 'pending',
              'origin': 'notification',
              'verification': 'unverified',
              'sourceName': 'Nequi',
              'counterparty': 'Ana',
              'reference': 'NQ-45',
              'method': 'Transferencia',
              'reportedStatus': 'Aprobada',
            },
          ],
        }),
      );

      final repository = await MovementRepository.open(directory);
      final saved = (await repository.listMovements()).single;
      final persisted = jsonDecode(await file.readAsString()) as Map;

      expect(persisted['version'], 3);
      expect(persisted['changeHistory'], isEmpty);
      expect(saved.id, 'old-detected');
      expect(saved.sourceName, 'Nequi');
      expect(saved.counterparty, 'Ana');
      expect(saved.reference, 'NQ-45');
      expect(saved.reportedStatus, 'Aprobada');
      expect(saved.verification, MovementVerification.unverified);
    },
  );

  test(
    'audits manual edits and refuses changes to external source rows',
    () async {
      final repository = await MovementRepository.open(directory);
      final manual = MoneyMovement(
        id: 'manual-audit',
        kind: MovementKind.expense,
        amountMinor: 25000,
        category: 'Mercado',
        note: 'Compra inicial',
        createdAt: DateTime.utc(2026, 10, 8),
      );
      final imported = MoneyMovement(
        id: 'bank-original',
        kind: MovementKind.income,
        amountMinor: 50000,
        category: 'Ingreso reportado',
        sourceName: 'Nequi',
        origin: MovementOrigin.notification,
        verification: MovementVerification.unverified,
        createdAt: DateTime.utc(2026, 10, 8),
      );
      await repository.addMovement(manual);
      await repository.addMovement(imported);

      final changed = MoneyMovement(
        id: manual.id,
        kind: manual.kind,
        amountMinor: 27500,
        category: 'Mercado',
        note: 'Compra corregida',
        createdAt: manual.createdAt,
      );
      expect(await repository.updateManualMovement(changed), isTrue);
      expect(
        await repository.updateManualMovement(
          MoneyMovement(
            id: imported.id,
            kind: MovementKind.income,
            amountMinor: 51000,
            category: 'Editado',
            createdAt: imported.createdAt,
            origin: MovementOrigin.notification,
            verification: MovementVerification.userReviewed,
          ),
        ),
        isFalse,
      );

      final reopened = await MovementRepository.open(directory);
      final saved = await reopened.listMovements();
      final savedManual = saved.singleWhere((row) => row.id == manual.id);
      final savedImported = saved.singleWhere((row) => row.id == imported.id);
      final revisions = await reopened.listMovementChanges(manual.id);
      expect(savedManual.amountMinor, 27500);
      expect(savedManual.note, 'Compra corregida');
      expect(savedImported.amountMinor, 50000);
      expect(savedImported.category, 'Ingreso reportado');
      expect(revisions, hasLength(1));
      expect(revisions.single.before['amountMinor'], 25000);
      expect(revisions.single.after['amountMinor'], 27500);
      expect(revisions.single.before['note'], 'Compra inicial');
    },
  );

  test('rejects an unsupported currency code', () {
    expect(
      () => MoneyMovement(
        id: 'bad-currency',
        kind: MovementKind.expense,
        amountMinor: 10,
        currency: 'PESOS',
        category: 'Test',
        createdAt: DateTime.utc(2026),
      ),
      throwsArgumentError,
    );
  });

  test(
    'recovers a valid backup when the primary ledger is corrupted',
    () async {
      await directory.create(recursive: true);
      final path = '${directory.path}${Platform.pathSeparator}movements.json';
      final primary = File(path);
      await primary.writeAsString('{corrupt');
      await File('$path.bak').writeAsString(
        jsonEncode({
          'version': 2,
          'movements': [
            {
              'id': 'recovered-1',
              'kind': 'income',
              'amountMinor': 5000,
              'currency': 'COP',
              'category': 'Recuperado',
              'note': '',
              'createdAt': '2026-10-08T00:00:00.000Z',
              'syncState': 'pending',
            },
          ],
        }),
      );

      final repository = await MovementRepository.open(directory);

      expect((await repository.listMovements()).single.id, 'recovered-1');
      expect(jsonDecode(await primary.readAsString())['version'], 3);
    },
  );
}
