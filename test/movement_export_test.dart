import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bruges_finanzas_360/domain/money_movement.dart';
import 'package:bruges_finanzas_360/services/movement_export_service.dart';

void main() {
  test('exports actual movement data as escaped CSV and JSON files', () async {
    final directory = await Directory.systemTemp.createTemp('bruges-export-');
    addTearDown(() => directory.delete(recursive: true));
    final movement = MoneyMovement(
      id: 'export-1',
      kind: MovementKind.expense,
      amountMinor: 12345,
      currency: 'USD',
      category: 'Café, oficina',
      note: 'Dijo "listo"',
      origin: MovementOrigin.notification,
      verification: MovementVerification.unverified,
      sourceName: 'Nequi',
      counterparty: 'Andrea',
      reference: 'ref-9087',
      createdAt: DateTime.utc(2026, 10, 8),
    );

    final csv = MovementExportService.toCsv([movement]);
    final json = MovementExportService.toJson([movement]);
    final csvFile = await MovementExportService.writeCsv([movement], directory);
    final jsonFile = await MovementExportService.writeJson([
      movement,
    ], directory);

    expect(csv, contains('"Café, oficina"'));
    expect(csv, contains('"Dijo ""listo"""'));
    expect(csv, contains('"notification"'));
    expect(csv, contains('"Andrea"'));
    expect((jsonDecode(json) as List).single['amountMinor'], 12345);
    expect((jsonDecode(json) as List).single['reference'], 'ref-9087');
    expect(await csvFile.length(), greaterThan(0));
    expect(await jsonFile.length(), greaterThan(0));
  });
}
