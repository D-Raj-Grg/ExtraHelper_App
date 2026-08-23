import 'package:extrahelper/data/supabase/settings_repository.dart';
import 'package:extrahelper/features/settings/charges_form.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('validateServiceCharge', () {
    test('accepts the whole legal range', () {
      expect(validateServiceCharge('0'), isNull);
      expect(validateServiceCharge('10'), isNull);
      expect(validateServiceCharge('12.5'), isNull);
      expect(validateServiceCharge('100'), isNull);
      expect(validateServiceCharge(' 10 '), isNull);
    });

    test('refuses anything outside it, in the web app words', () {
      const message = 'Service charge must be between 0 and 100.';
      expect(validateServiceCharge('100.01'), message);
      expect(validateServiceCharge('-1'), message);
    });

    test('refuses what is not a number at all', () {
      expect(validateServiceCharge('abc'), 'Service charge must be a number.');
      expect(validateServiceCharge(''), 'Service charge must be a number.');
    });
  });

  group('validatePackagingFee', () {
    test('accepts zero and any positive amount', () {
      expect(validatePackagingFee('0'), isNull);
      expect(validatePackagingFee('25.50'), isNull);
      // No upper bound: this is money, not a percentage, and a currency with
      // small units legitimately runs into the thousands.
      expect(validatePackagingFee('5000'), isNull);
    });

    test('refuses a negative fee', () {
      expect(validatePackagingFee('-0.01'), "Packaging fee can't be negative.");
    });

    test('refuses what is not a number', () {
      expect(validatePackagingFee('free'), 'Packaging fee must be a number.');
    });
  });

  group('tax rule validation', () {
    test('a rule needs a name', () {
      expect(validateTaxRuleName('  '), 'Give the rule a name.');
      expect(validateTaxRuleName('VAT'), isNull);
    });

    test('a rate is a percentage between 0 and 100', () {
      expect(validateTaxRuleRate('13'), isNull);
      expect(validateTaxRuleRate('0'), isNull);
      expect(validateTaxRuleRate('100'), isNull);
      expect(validateTaxRuleRate('101'), 'Rate must be between 0 and 100.');
      expect(validateTaxRuleRate('-1'), 'Rate must be between 0 and 100.');
      expect(validateTaxRuleRate('thirteen'), 'Rate must be a number.');
    });
  });

  group('formatting', () {
    test('a whole rate loses its decimal point, a fractional one keeps it', () {
      expect(formatRate(13), '13');
      expect(formatRate(12.5), '12.5');
      expect(formatRate(0), '0');
    });

    test('a fee always reads as money', () {
      expect(formatFee(25.5), '25.50');
      expect(formatFee(0), '0.00');
    });

    test('a rule describes itself the way the row shows it', () {
      expect(
        describeTaxRule(const TaxRule(name: 'VAT', rate: 13, inclusive: false)),
        '13% · Exclusive',
      );
      expect(
        describeTaxRule(
          const TaxRule(name: 'Levy', rate: 2.5, inclusive: true),
        ),
        '2.5% · Inclusive',
      );
    });
  });

  group('TaxRuleDraft', () {
    test('editing a rule keeps the row it belongs to', () {
      const draft = TaxRuleDraft(
        7,
        TaxRule(name: 'VAT', rate: 13, inclusive: false),
      );
      final edited = draft.withRule(
        const TaxRule(name: 'GST', rate: 18, inclusive: false),
      );

      // The id is the row's identity: rename a rule to something another rule
      // is already called and a content-derived key would move the caret.
      expect(edited.id, 7);
      expect(edited.rule.name, 'GST');
    });
  });
}
