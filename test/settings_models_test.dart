import 'package:extrahelper/data/supabase/settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// A verbatim `tenant_settings` row, as PostgREST returns it — including the
/// numerics as strings, which is what a hand-typed fixture always gets wrong.
const _row = <String, dynamic>{
  'currency': 'NPR',
  'timezone': 'Asia/Kathmandu',
  'day_cutoff_minutes': 240,
  'service_charge': '10.00',
  'packaging_fee': '25.50',
  'tax_rules': [
    {'name': 'VAT', 'rate': 13, 'inclusive': false},
    {'name': 'Service tax', 'rate': 2.5, 'inclusive': true},
  ],
  'receipt_template': {
    'header': 'Sekuwa Station',
    'footer': 'Thank you',
    'terms': 'No refunds after 24h',
    'qr_caption': 'Scan to pay',
    'logo_url': 'https://cdn.example/logo.png?v=1',
    'print_assets': {
      'logo': {
        '384': {'w': 384, 'h': 96, 'data': 'AAA='},
        '576': {'w': 576, 'h': 144, 'data': 'BBB='},
      },
    },
  },
  'block_negative_stock': true,
  'payment_gateway': 'manual',
  'printing_mode': 'cloud',
  'qr_auto_fire': false,
};

void main() {
  group('TenantSettings.fromJson', () {
    test('reads a full row', () {
      final settings = TenantSettings.fromJson(_row);

      expect(settings.currency, 'NPR');
      expect(settings.timezone, 'Asia/Kathmandu');
      expect(settings.dayCutoffMinutes, 240);
      expect(settings.blockNegativeStock, isTrue);
      expect(settings.qrAutoFire, isFalse);
      expect(settings.paymentGateway, 'manual');
      expect(settings.printingMode, 'cloud');
    });

    test('coerces numerics that arrive as strings', () {
      final settings = TenantSettings.fromJson(_row);

      expect(settings.serviceCharge, 10);
      // Currency units, not cents — 25.50 is twenty-five and a half rupees.
      expect(settings.packagingFee, 25.5);
    });

    test('reads tax rules in order, keeping fractional rates', () {
      final rules = TenantSettings.fromJson(_row).taxRules;

      expect(rules.map((r) => r.name), ['VAT', 'Service tax']);
      expect(rules.first.rate, 13);
      expect(rules.first.inclusive, isFalse);
      expect(rules.last.rate, 2.5);
      expect(rules.last.inclusive, isTrue);
    });

    test('a missing row is the column defaults, not an error', () {
      final settings = TenantSettings.fromJson(null);

      expect(settings.currency, 'USD');
      expect(settings.timezone, 'UTC');
      expect(settings.dayCutoffMinutes, 0);
      expect(settings.serviceCharge, 0);
      expect(settings.packagingFee, 0);
      expect(settings.taxRules, isEmpty);
      expect(settings.paymentGateway, 'sandbox');
    });

    test('qr_auto_fire defaults on, because the column does', () {
      expect(TenantSettings.fromJson(const {}).qrAutoFire, isTrue);
      expect(
        TenantSettings.fromJson(const {'qr_auto_fire': false}).qrAutoFire,
        isFalse,
      );
    });

    test('an empty template and an empty rule list are not errors', () {
      final settings = TenantSettings.fromJson(const {
        'tax_rules': <dynamic>[],
        'receipt_template': <String, dynamic>{},
      });

      expect(settings.taxRules, isEmpty);
      expect(settings.receipt.header, '');
      expect(settings.receipt.logoUrl, isNull);
      expect(settings.receipt.printAssets, isEmpty);
    });
  });

  group('ReceiptTemplate', () {
    test('reads the wording and the URLs', () {
      final receipt = TenantSettings.fromJson(_row).receipt;

      expect(receipt.header, 'Sekuwa Station');
      expect(receipt.footer, 'Thank you');
      expect(receipt.terms, 'No refunds after 24h');
      expect(receipt.qrCaption, 'Scan to pay');
      expect(receipt.logoUrl, 'https://cdn.example/logo.png?v=1');
    });

    test('an empty URL is no image, not an image at ""', () {
      final receipt = ReceiptTemplate.fromJson(const {'logo_url': '   '});
      expect(receipt.logoUrl, isNull);
    });

    test('exposes which roll widths an image is prepared for', () {
      final receipt = TenantSettings.fromJson(_row).receipt;

      expect(receipt.widthsFor('logo'), {'384', '576'});
      // Never uploaded: no widths, and no crash reading for it.
      expect(receipt.widthsFor('qr'), isEmpty);
    });

    test('the asset map is carried through whole', () {
      final assets = TenantSettings.fromJson(_row).receipt.printAssets;

      // Whole, because `merge_receipt_template` merges shallowly: attaching a
      // QR has to send the logo's bitmaps back untouched or they are dropped.
      expect(assets.keys, ['logo']);
      expect((assets['logo'] as Map)['384'], {
        'w': 384,
        'h': 96,
        'data': 'AAA=',
      });
    });
  });

  group('TaxRule', () {
    test('round-trips through toJson', () {
      const rule = TaxRule(name: 'VAT', rate: 12.5, inclusive: true);
      expect(TaxRule.fromJson(rule.toJson()).rate, 12.5);
      expect(TaxRule.fromJson(rule.toJson()).inclusive, isTrue);
    });

    test('a missing rate reads as zero rather than throwing', () {
      final rule = TaxRule.fromJson(const {'name': 'VAT'});
      expect(rule.rate, 0);
      expect(rule.inclusive, isFalse);
    });
  });

  group('the option lists the server also validates against', () {
    test('currencies and timezones match the web', () {
      expect(settingsCurrencies, hasLength(10));
      expect(settingsCurrencies, contains('NPR'));
      expect(settingsTimezones.first, 'UTC');
      expect(settingsTimezones, contains('Asia/Kathmandu'));
    });

    test('day cutoffs are the seven half-day options', () {
      expect(dayCutoffOptions.keys, [0, 60, 120, 180, 240, 300, 360]);
      // The column checks `>= 0 and < 720`; every offered value is inside it.
      expect(dayCutoffOptions.keys.every((m) => m >= 0 && m < 720), isTrue);
    });

    test('payment gateways are the two the action allows', () {
      expect(paymentGateways.keys.toSet(), {'sandbox', 'manual'});
    });
  });
}
