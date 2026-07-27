import 'package:extrahelper/core/format/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('money', () {
    test('formats cents with the tenant currency, never a hardcoded one', () {
      expect(money(108000, 'NPR'), contains('1,080.00'));
      expect(money(108000, 'NPR'), contains('NPR'));
      expect(money(1250, 'USD'), r'$12.50');
    });

    test('handles zero and negatives (refund lines)', () {
      expect(money(0, 'USD'), r'$0.00');
      expect(money(-500, 'USD'), contains('5.00'));
    });

    test('an unknown currency code still renders, using the code itself', () {
      expect(money(1000, 'XZY'), contains('10.00'));
      expect(money(1000, 'XZY'), contains('XZY'));
    });
  });

  group('moneyRange', () {
    test('collapses to one price when the ends match', () {
      expect(moneyRange(45000, 45000, 'NPR'), money(45000, 'NPR'));
    });

    test('prints the currency once, with an en dash', () {
      // The real case from the web bug: a variant dish is orderable only at
      // 1,080 or 1,680, so the tile must show the span, not the base price.
      final text = moneyRange(108000, 168000, 'NPR');
      expect(text, contains('1,080.00'));
      expect(text, contains('1,680.00'));
      expect(text, contains('–')); // en dash, not a hyphen
      expect('NPR'.allMatches(text).length, 1);
    });

    test('symbol currencies collapse the prefix too', () {
      final text = moneyRange(1000, 2000, 'USD');
      expect(text, r'$10.00 – 20.00');
    });
  });
}
