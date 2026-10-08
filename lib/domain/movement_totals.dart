import 'money_movement.dart';

class MovementTotals {
  MovementTotals._(this._amounts);

  final Map<String, Map<MovementKind, int>> _amounts;

  factory MovementTotals.fromMovements(Iterable<MoneyMovement> movements) {
    final amounts = <String, Map<MovementKind, int>>{};
    for (final movement in movements) {
      final currencyAmounts = amounts.putIfAbsent(
        movement.currency,
        () => {MovementKind.income: 0, MovementKind.expense: 0},
      );
      currencyAmounts.update(
        movement.kind,
        (total) => total + movement.amountMinor,
        ifAbsent: () => movement.amountMinor,
      );
    }
    return MovementTotals._(amounts);
  }

  Set<String> get currencies => Set.unmodifiable(_amounts.keys);

  int amount(String currency, MovementKind kind) =>
      _amounts[currency]?[kind] ?? 0;

  int balance(String currency) =>
      amount(currency, MovementKind.income) -
      amount(currency, MovementKind.expense);
}
