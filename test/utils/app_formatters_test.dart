import 'package:boundary/formatters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppFormatters.formatCurrency', () {
    test('uses the symbol it is given', () {
      expect(
        AppFormatters.formatCurrency(1234.5, 'en', symbol: 'RM '),
        'RM 1,234.50',
      );
    });

    test('puts the minus sign before the symbol for negative values', () {
      expect(
        AppFormatters.formatCurrency(-3, 'en', symbol: 'RM '),
        '-RM 3.00',
      );
    });
  });
}
