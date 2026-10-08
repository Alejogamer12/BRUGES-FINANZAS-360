import 'package:flutter_test/flutter_test.dart';
import 'package:bruges_finanzas_360/domain/money_movement.dart';
import 'package:bruges_finanzas_360/services/movement_filter.dart';

void main() {
  test('combines text, type, currency, and inclusive date filters', () {
    final rows = [
      MoneyMovement(
        id: 'usd-later',
        kind: MovementKind.expense,
        amountMinor: 100,
        currency: 'USD',
        category: 'Café',
        note: 'Centro',
        createdAt: DateTime.utc(2026, 10, 8, 12),
      ),
      MoneyMovement(
        id: 'cop-earlier',
        kind: MovementKind.income,
        amountMinor: 5000,
        currency: 'COP',
        category: 'Salario',
        createdAt: DateTime.utc(2026, 10, 8, 8),
      ),
      MoneyMovement(
        id: 'usd-old',
        kind: MovementKind.expense,
        amountMinor: 200,
        currency: 'USD',
        category: 'Café',
        createdAt: DateTime.utc(2026, 10, 6),
      ),
      MoneyMovement(
        id: 'detected-nequi',
        kind: MovementKind.income,
        amountMinor: 5000,
        category: 'Transferencia detectada',
        sourceName: 'Nequi',
        counterparty: 'Andrea',
        reference: 'REF-7788',
        origin: MovementOrigin.notification,
        verification: MovementVerification.unverified,
        createdAt: DateTime.utc(2026, 10, 8, 10),
      ),
    ];

    final filtered = filterMovements(
      rows,
      text: 'centro',
      kind: MovementKind.expense,
      currency: 'USD',
      from: DateTime.utc(2026, 10, 8),
      to: DateTime.utc(2026, 10, 8),
    );

    expect(filtered.map((movement) => movement.id), ['usd-later']);
  });

  test('filters by entity and searches counterparty/reference metadata', () {
    final rows = [
      MoneyMovement(
        id: 'nequi-row',
        kind: MovementKind.income,
        amountMinor: 5000,
        category: 'Transferencia detectada',
        sourceName: 'Nequi',
        counterparty: 'Andrea',
        reference: 'REF-7788',
        origin: MovementOrigin.notification,
        createdAt: DateTime.utc(2026, 10, 8),
      ),
      MoneyMovement(
        id: 'davi-row',
        kind: MovementKind.income,
        amountMinor: 5000,
        category: 'Transferencia detectada',
        sourceName: 'DaviPlata',
        createdAt: DateTime.utc(2026, 10, 8),
      ),
    ];

    final filtered = filterMovements(
      rows,
      text: 'REF-7788',
      sourceName: 'Nequi',
    );

    expect(filtered.map((movement) => movement.id), ['nequi-row']);
  });

  test('searches movement amounts in the formatted major-unit value', () {
    final rows = [
      MoneyMovement(
        id: 'market',
        kind: MovementKind.expense,
        amountMinor: 25000,
        category: 'Mercado',
        createdAt: DateTime.utc(2026, 10, 8),
      ),
      MoneyMovement(
        id: 'transport',
        kind: MovementKind.expense,
        amountMinor: 3200,
        category: 'Transporte',
        createdAt: DateTime.utc(2026, 10, 7),
      ),
    ];

    expect(
      filterMovements(rows, text: '25.000').map((movement) => movement.id),
      ['market'],
    );
  });
}
