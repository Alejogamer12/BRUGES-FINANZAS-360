import 'package:flutter_test/flutter_test.dart';
import 'package:bruges_finanzas_360/domain/money_movement.dart';
import 'package:bruges_finanzas_360/domain/movement_totals.dart';

void main() {
  test('totals are grouped by currency and movement kind', () {
    final movements = [
      MoneyMovement(
        id: 'cop-in',
        kind: MovementKind.income,
        amountMinor: 100000,
        currency: 'COP',
        category: 'Salario',
        createdAt: DateTime.utc(2026),
      ),
      MoneyMovement(
        id: 'usd-in',
        kind: MovementKind.income,
        amountMinor: 100,
        currency: 'USD',
        category: 'Pago',
        createdAt: DateTime.utc(2026),
      ),
      MoneyMovement(
        id: 'usd-out',
        kind: MovementKind.expense,
        amountMinor: 25,
        currency: 'USD',
        category: 'Comida',
        createdAt: DateTime.utc(2026),
      ),
    ];

    final totals = MovementTotals.fromMovements(movements);

    expect(totals.amount('COP', MovementKind.income), 100000);
    expect(totals.amount('USD', MovementKind.income), 100);
    expect(totals.amount('USD', MovementKind.expense), 25);
    expect(totals.balance('USD'), 75);
    expect(totals.amount('COP', MovementKind.expense), 0);
  });
}
