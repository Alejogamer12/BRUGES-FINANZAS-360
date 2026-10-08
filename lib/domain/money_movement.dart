import 'currency.dart';

enum MovementKind { income, expense }

enum MovementSyncState { pending, confirmed }

enum MovementOrigin { manual, notification, imported, officialIntegration }

enum MovementVerification {
  userProvided,
  unverified,
  userReviewed,
  userConfirmed,
}

class MoneyMovement {
  MoneyMovement({
    required this.id,
    required this.kind,
    required this.amountMinor,
    required this.category,
    required this.createdAt,
    this.currency = 'COP',
    this.note = '',
    this.syncState = MovementSyncState.pending,
    this.origin = MovementOrigin.manual,
    this.verification = MovementVerification.userProvided,
    this.sourceName,
    this.counterparty,
    this.reference,
    this.method,
    this.reportedStatus,
  }) {
    if (amountMinor <= 0) {
      throw ArgumentError.value(
        amountMinor,
        'amountMinor',
        'Debe ser mayor que cero.',
      );
    }
    if (!supportedCurrencyCodes.contains(currency)) {
      throw ArgumentError.value(currency, 'currency', 'Moneda no admitida.');
    }
  }

  final String id;
  final MovementKind kind;
  final int amountMinor;
  final String currency;
  final String category;
  final String note;
  final DateTime createdAt;
  final MovementSyncState syncState;
  final MovementOrigin origin;
  final MovementVerification verification;
  final String? sourceName;
  final String? counterparty;
  final String? reference;
  final String? method;
  final String? reportedStatus;

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'amountMinor': amountMinor,
    'currency': currency,
    'category': category,
    'note': note,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'syncState': syncState.name,
    'origin': origin.name,
    'verification': verification.name,
    'sourceName': sourceName,
    'counterparty': counterparty,
    'reference': reference,
    'method': method,
    'reportedStatus': reportedStatus,
  };

  factory MoneyMovement.fromJson(Map<String, Object?> json) {
    return MoneyMovement(
      id: json['id']! as String,
      kind: MovementKind.values.byName(json['kind']! as String),
      amountMinor: json['amountMinor']! as int,
      currency: json['currency'] as String? ?? 'COP',
      category: json['category']! as String,
      note: json['note'] as String? ?? '',
      createdAt: DateTime.parse(json['createdAt']! as String),
      syncState: MovementSyncState.values.byName(
        json['syncState'] as String? ?? MovementSyncState.pending.name,
      ),
      origin: MovementOrigin.values.byName(
        json['origin'] as String? ?? MovementOrigin.manual.name,
      ),
      verification: MovementVerification.values.byName(
        json['verification'] as String? ??
            MovementVerification.userProvided.name,
      ),
      sourceName: json['sourceName'] as String?,
      counterparty: json['counterparty'] as String?,
      reference: json['reference'] as String?,
      method: json['method'] as String?,
      reportedStatus: json['reportedStatus'] as String?,
    );
  }
}
