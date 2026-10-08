import '../domain/money_movement.dart';

enum MovementGroupPeriod { day, week, month, year }

class MovementGroup {
  const MovementGroup({
    required this.period,
    required this.start,
    required this.movements,
  });

  final MovementGroupPeriod period;
  final DateTime start;
  final List<MoneyMovement> movements;

  String get label {
    final date =
        '${start.day.toString().padLeft(2, '0')}/'
        '${start.month.toString().padLeft(2, '0')}/${start.year}';
    return switch (period) {
      MovementGroupPeriod.day => date,
      MovementGroupPeriod.week => 'Semana del $date',
      MovementGroupPeriod.month =>
        '${start.month.toString().padLeft(2, '0')}/${start.year}',
      MovementGroupPeriod.year => start.year.toString(),
    };
  }
}

List<MovementGroup> groupMovements(
  Iterable<MoneyMovement> movements, {
  required MovementGroupPeriod period,
}) {
  final grouped = <DateTime, List<MoneyMovement>>{};
  for (final movement in movements) {
    final local = movement.createdAt.toLocal();
    final start = switch (period) {
      MovementGroupPeriod.day => DateTime(local.year, local.month, local.day),
      MovementGroupPeriod.week => DateTime(
        local.year,
        local.month,
        local.day - (local.weekday - 1),
      ),
      MovementGroupPeriod.month => DateTime(local.year, local.month),
      MovementGroupPeriod.year => DateTime(local.year),
    };
    grouped.putIfAbsent(start, () => <MoneyMovement>[]).add(movement);
  }

  final starts = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final start in starts)
      MovementGroup(
        period: period,
        start: start,
        movements: List.unmodifiable(
          grouped[start]!..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
        ),
      ),
  ];
}
