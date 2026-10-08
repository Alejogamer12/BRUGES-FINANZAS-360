import 'package:intl/intl.dart';

const currencyNames = <String, String>{
  'COP': 'Peso colombiano',
  'USD': 'Dólar estadounidense',
  'EUR': 'Euro',
  'MXN': 'Peso mexicano',
  'GBP': 'Libra esterlina',
  'CAD': 'Dólar canadiense',
  'BRL': 'Real brasileño',
  'PEN': 'Sol peruano',
  'CLP': 'Peso chileno',
  'ARS': 'Peso argentino',
};

Set<String> get supportedCurrencyCodes => currencyNames.keys.toSet();

int currencyDecimalDigits(String code) {
  if (!currencyNames.containsKey(code)) {
    throw ArgumentError.value(code, 'code', 'Moneda no admitida.');
  }
  return code == 'COP' || code == 'CLP' ? 0 : 2;
}

int? parseMajorAmount(String input, String currency) {
  final digits = currencyDecimalDigits(currency);
  var normalized = input.trim().replaceAll(' ', '');
  if (normalized.isEmpty) return null;
  if (normalized.contains(',') && normalized.contains('.')) {
    normalized = normalized.lastIndexOf(',') > normalized.lastIndexOf('.')
        ? normalized.replaceAll('.', '').replaceFirst(',', '.')
        : normalized.replaceAll(',', '');
  } else if (normalized.contains(',')) {
    normalized = normalized.replaceFirst(',', '.');
  } else if (digits == 0 &&
      (RegExp(r'^\d{1,3}(\.\d{3})+$').hasMatch(normalized) ||
          RegExp(r'^\d{1,3}(,\d{3})+$').hasMatch(normalized))) {
    normalized = normalized.replaceAll(RegExp(r'[.,]'), '');
  } else if (normalized.split('.').length > 2 &&
      RegExp(r'^\d{1,3}(\.\d{3})+$').hasMatch(normalized)) {
    normalized = normalized.replaceAll('.', '');
  }
  final parts = normalized.split('.');
  if (parts.length > 2 || !RegExp(r'^\d+$').hasMatch(parts.first)) {
    return null;
  }
  final fraction = parts.length == 2 ? parts[1] : '';
  if (fraction.isNotEmpty && !RegExp(r'^\d+$').hasMatch(fraction)) return null;
  if (fraction.length > digits) return null;
  final paddedFraction = fraction.padRight(digits, '0');
  final scale = BigInt.from(10).pow(digits);
  final whole = BigInt.parse(parts.first);
  final minor =
      whole * scale +
      (paddedFraction.isEmpty ? BigInt.zero : BigInt.parse(paddedFraction));
  if (minor <= BigInt.zero || minor > BigInt.from(0x7fffffffffffffff)) {
    return null;
  }
  return minor.toInt();
}

String formatMinorAmount(
  int amountMinor,
  String currency, {
  String locale = 'es_CO',
}) {
  final digits = currencyDecimalDigits(currency);
  final major = amountMinor / (digits == 0 ? 1 : 100);
  return NumberFormat.currency(
    locale: locale,
    name: currency,
    decimalDigits: digits,
  ).format(major);
}
