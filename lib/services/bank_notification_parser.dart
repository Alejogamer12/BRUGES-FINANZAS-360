import '../domain/currency.dart';
import '../domain/money_movement.dart';

const bankNotificationPackages = <String, String>{
  'com.nequi.MobileApp': 'Nequi',
  'co.com.bancolombia.personas.superapp': 'Mi Bancolombia',
  'com.davivienda.daviplataapp': 'DaviPlata',
  'com.avalsolucionesdigitalessa.dale_app_embedded': 'dale!',
  'com.movilred.subscriber': 'MOVii',
};

class BankNotificationObservation {
  const BankNotificationObservation({
    required this.id,
    required this.source,
    required this.packageName,
    required this.kind,
    required this.amountMinor,
    required this.currency,
    required this.observedAt,
    this.counterparty,
    this.reference,
    this.method,
    this.reportedStatus,
    this.reviewReason,
    this.reviewState = 'review',
  });

  final String id;
  final String source;
  final String packageName;
  final MovementKind? kind;
  final int? amountMinor;
  final String? currency;
  final DateTime observedAt;
  final String? counterparty;
  final String? reference;
  final String? method;
  final String? reportedStatus;
  final String? reviewReason;

  bool get isReadyForAutomaticRegistration =>
      kind != null && amountMinor != null && currency != null;
  final String reviewState;

  Map<String, Object?> toJson() => {
    'id': id,
    'source': source,
    'packageName': packageName,
    'kind': kind?.name,
    'amountMinor': amountMinor,
    'currency': currency,
    'observedAt': observedAt.toUtc().toIso8601String(),
    'counterparty': counterparty,
    'reference': reference,
    'method': method,
    'reportedStatus': reportedStatus,
    'reviewReason': reviewReason,
    'reviewState': reviewState,
  };

  factory BankNotificationObservation.fromJson(Map<String, Object?> json) =>
      BankNotificationObservation(
        id: json['id']! as String,
        source: json['source']! as String,
        packageName: json['packageName']! as String,
        kind: json['kind'] is String
            ? MovementKind.values.byName(json['kind']! as String)
            : null,
        amountMinor: json['amountMinor'] as int?,
        currency: json['currency'] as String?,
        observedAt: json['observedAt'] is int
            ? DateTime.fromMillisecondsSinceEpoch(
                json['observedAt']! as int,
                isUtc: true,
              )
            : DateTime.parse(json['observedAt']! as String),
        counterparty: json['counterparty'] as String?,
        reference: json['reference'] as String?,
        method: json['method'] as String?,
        reportedStatus: json['reportedStatus'] as String?,
        reviewReason: json['reviewReason'] as String?,
        reviewState: json['reviewState'] as String? ?? 'review',
      );

  BankNotificationObservation reviewed({required bool accepted}) =>
      BankNotificationObservation(
        id: id,
        source: source,
        packageName: packageName,
        kind: kind,
        amountMinor: amountMinor,
        currency: currency,
        observedAt: observedAt,
        counterparty: counterparty,
        reference: reference,
        method: method,
        reportedStatus: reportedStatus,
        reviewReason: reviewReason,
        reviewState: accepted ? 'accepted' : 'dismissed',
      );

  MoneyMovement toMovement({bool reviewed = false}) {
    if (!isReadyForAutomaticRegistration) {
      throw StateError(
        'La observación necesita revisión antes de registrarse.',
      );
    }
    return MoneyMovement(
      id: id,
      kind: kind!,
      amountMinor: amountMinor!,
      currency: currency!,
      category: 'Transferencia detectada · $source',
      note: reviewed
          ? 'Revisado por el usuario; el aviso no es confirmación bancaria.'
          : 'Detectado mediante notificación; no es confirmación bancaria.',
      createdAt: observedAt,
      origin: MovementOrigin.notification,
      verification: reviewed
          ? MovementVerification.userReviewed
          : MovementVerification.unverified,
      sourceName: source,
      counterparty: counterparty,
      reference: reference,
      method: method,
      reportedStatus: reportedStatus,
    );
  }
}

class BankNotificationParser {
  BankNotificationObservation? parse({
    required String packageName,
    required String notificationKey,
    required String title,
    required String text,
    required DateTime observedAt,
  }) {
    final source = bankNotificationPackages[packageName];
    if (source == null || notificationKey.trim().isEmpty) return null;

    final content = '$title $text'.toLowerCase();
    final isIncome = RegExp(
      r'\b(recibiste|recibieron|recibida|recibido|abono|consignaci[oó]n\s+recibida|transferencia\s+recibida|te\s+lleg[oó]|te\s+enviaron|te\s+transfirieron)\b',
    ).hasMatch(content);
    final isExpense = RegExp(
      r'\b(pagaste|pag[oó]|compra|compraste|transferiste|enviaste|transferencia\s+enviada|retiro|retiraste|d[eé]bito|debito|pago\s+aprobado|pago\s+realizado)\b',
    ).hasMatch(content);
    final hasTransactionCue = RegExp(
      r'\b(recibiste|recibieron|recibida|recibido|abono|consignaci[oó]n|transferencia|transfirieron|pagaste|pag[oó]|compra|compraste|transferiste|enviaste|retiro|retiraste|d[eé]bito|debito|pago)\b',
    ).hasMatch(content);
    if (!hasTransactionCue) return null;

    final amountMatches = RegExp(
      r'(?:COP|COL\$|\$)\s*([0-9][0-9., ]*)',
      caseSensitive: false,
    ).allMatches('$title $text').toList();
    final amount = amountMatches.length != 1
        ? null
        : parseMajorAmount(amountMatches.single.group(1)!, 'COP');
    final kind = isIncome == isExpense
        ? null
        : isIncome
        ? MovementKind.income
        : MovementKind.expense;

    final reference = RegExp(
      r'\b(?:referencia|ref\.?|comprobante)\s*[:#-]?\s*([A-Z0-9-]{4,40})',
      caseSensitive: false,
    ).firstMatch('$title $text')?.group(1);
    final counterparty = RegExp(
      r"\b(?:de|a|para)\s+([A-Za-zÁÉÍÓÚÜÑáéíóúüñ][A-Za-zÁÉÍÓÚÜÑáéíóúüñ .'-]{1,38}?)(?=[.,;\n]|$)",
      caseSensitive: false,
    ).firstMatch('$title $text')?.group(1)?.trim();
    final methodMatch = RegExp(
      r'\b(Bre-B|PSE|QR|tarjeta|llave)\b',
      caseSensitive: false,
    ).firstMatch(content);
    final status = RegExp(
      r'\b(completada|completado|exitosa|exitoso|realizada|realizado|pendiente|procesando|rechazada|rechazado|fallida|fallido)\b',
    ).firstMatch(content)?.group(1);
    final reportedStatus = status == null
        ? null
        : RegExp(r'pendiente|procesando').hasMatch(status)
        ? 'pending_reported'
        : RegExp(r'rechazad|fallid').hasMatch(status)
        ? 'failed_reported'
        : 'completed_reported';

    return BankNotificationObservation(
      id: '$packageName:$notificationKey',
      source: source,
      packageName: packageName,
      kind: kind,
      amountMinor: amount,
      currency: amount == null ? null : 'COP',
      observedAt: observedAt.toUtc(),
      counterparty: counterparty?.isEmpty == true ? null : counterparty,
      reference: reference,
      method: methodMatch?.group(1),
      reportedStatus: reportedStatus,
      reviewReason: kind == null
          ? 'Tipo de movimiento ambiguo'
          : amount == null
          ? 'Importe no identificado'
          : null,
    );
  }
}
