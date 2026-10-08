import '../domain/money_movement.dart';

List<MoneyMovement> filterMovements(
  Iterable<MoneyMovement> movements, {
  String text = '',
  MovementKind? kind,
  String? currency,
  String? sourceName,
  MovementOrigin? origin,
  DateTime? from,
  DateTime? to,
}) {
  final needle = text.trim().toLowerCase();
  final start = from == null ? null : DateTime(from.year, from.month, from.day);
  final endExclusive = to == null
      ? null
      : DateTime(to.year, to.month, to.day + 1);
  final result = movements.where((movement) {
    if (kind != null && movement.kind != kind) return false;
    if (currency != null && movement.currency != currency) return false;
    if (sourceName != null && movement.sourceName != sourceName) return false;
    if (origin != null && movement.origin != origin) return false;
    if (needle.isNotEmpty &&
        !'${movement.category} ${movement.note} ${movement.sourceName ?? ''} ${movement.counterparty ?? ''} ${movement.reference ?? ''} ${movement.method ?? ''}'
            .toLowerCase()
            .contains(needle)) {
      return false;
    }
    final createdAt = movement.createdAt.toLocal();
    if (start != null && createdAt.isBefore(start)) return false;
    if (endExclusive != null && !createdAt.isBefore(endExclusive)) return false;
    return true;
  }).toList();
  result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return result;
}
