import 'package:flutter_test/flutter_test.dart';
import 'package:bruges_finanzas_360/domain/money_movement.dart';
import 'package:bruges_finanzas_360/services/movement_grouping.dart';

MoneyMovement row(String id, DateTime date) => MoneyMovement(
  id: id,
  kind: MovementKind.expense,
  amountMinor: 100,
  category: 'Mercado',
  createdAt: date,
);

void main() {
  final monday = DateTime(2026, 10, 5, 9);

  test('groups movements by local calendar day, newest group first', () {
    final groups = groupMovements([
      row('old-day', DateTime(2026, 10, 4, 23)),
      row('same-day-later', DateTime(2026, 10, 5, 16)),
      row('same-day-earlier', DateTime(2026, 10, 5, 8)),
    ], period: MovementGroupPeriod.day);

    expect(groups.map((group) => group.label), ['05/10/2026', '04/10/2026']);
    expect(groups.first.movements.map((movement) => movement.id), [
      'same-day-later',
      'same-day-earlier',
    ]);
  });

  test('groups weeks from Monday and keeps adjacent weeks separate', () {
    final groups = groupMovements([
      row('monday', monday),
      row('sunday', DateTime(2026, 10, 11, 21)),
      row('next-monday', DateTime(2026, 10, 12, 8)),
    ], period: MovementGroupPeriod.week);

    expect(groups.map((group) => group.label), [
      'Semana del 12/10/2026',
      'Semana del 05/10/2026',
    ]);
    expect(groups.last.movements, hasLength(2));
  });

  test('groups across months and years using calendar boundaries', () {
    final rows = [
      row('january', DateTime(2025, 1, 1)),
      row('december', DateTime(2025, 12, 31)),
      row('next-year', DateTime(2026, 1, 1)),
    ];

    expect(
      groupMovements(
        rows,
        period: MovementGroupPeriod.month,
      ).map((group) => group.label),
      ['01/2026', '12/2025', '01/2025'],
    );
    expect(
      groupMovements(
        rows,
        period: MovementGroupPeriod.year,
      ).map((group) => group.label),
      ['2026', '2025'],
    );
  });
}
