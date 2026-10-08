import 'package:flutter_test/flutter_test.dart';
import 'package:bruges_finanzas_360/domain/currency.dart';

void main() {
  test('parses major units exactly into currency minor units', () {
    expect(parseMajorAmount('1.234.567', 'COP'), 1234567);
    expect(parseMajorAmount('25.000', 'COP'), 25000);
    expect(parseMajorAmount('1250,75', 'USD'), 125075);
    expect(parseMajorAmount('1.250,75', 'EUR'), 125075);
    expect(parseMajorAmount('0,001', 'USD'), isNull);
  });
}
