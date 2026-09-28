import 'package:extrahelper/data/supabase/coupons_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// `list_coupons` rows as PostgREST hands them over: `numeric` and `bigint`
/// arrive as strings, nullable columns as null, `order_types` as a list or
/// null.
void main() {
  group('Coupon.fromRow', () {
    test('parses a full row, with bigint and numeric as strings', () {
      final c = Coupon.fromRow({
        'id': 'cp-1',
        'code': 'save10-7kq2',
        'name': 'Dashain flyer',
        'type': 'percent',
        'value': '10.00',
        'is_active': true,
        'valid_from': '2026-09-01T00:00:00+00:00',
        'valid_to': '2026-10-01T00:00:00+00:00',
        'usage_limit': 100,
        'used_count': '12',
        'min_subtotal_cents': '50000',
        'once_per_customer': true,
        'order_types': ['dine_in', 'pickup'],
        'created_at': '2026-08-30T10:00:00+00:00',
        'redemptions': '12',
        'discount_given_cents': '61200',
        'last_redeemed_at': '2026-09-20T12:00:00+00:00',
      });
      expect(c.code, 'SAVE10-7KQ2');
      expect(c.name, 'Dashain flyer');
      expect(c.isPercent, isTrue);
      expect(c.value, 10);
      expect(c.usageLimit, 100);
      expect(c.usedCount, 12);
      expect(c.minSubtotalCents, 50000);
      expect(c.oncePerCustomer, isTrue);
      expect(c.orderTypes, ['dine_in', 'pickup']);
      expect(c.redemptions, 12);
      expect(c.discountGivenCents, 61200);
      expect(c.codeLocked, isTrue);
      expect(c.validTo, DateTime.utc(2026, 10, 1));
    });

    test('nulls stay null and an unused coupon is not locked', () {
      final c = Coupon.fromRow({
        'id': 'cp-2',
        'code': 'FLAT200',
        'name': null,
        'type': 'flat',
        'value': 200,
        'is_active': false,
        'valid_from': null,
        'valid_to': null,
        'usage_limit': null,
        'used_count': 0,
        'min_subtotal_cents': 0,
        'once_per_customer': false,
        'order_types': null,
        'created_at': '2026-08-30T10:00:00+00:00',
        'redemptions': 0,
        'discount_given_cents': 0,
        'last_redeemed_at': null,
      });
      expect(c.name, isNull);
      expect(c.isPercent, isFalse);
      expect(c.usageLimit, isNull);
      expect(c.validFrom, isNull);
      expect(c.orderTypes, isNull);
      expect(c.codeLocked, isFalse);
      expect(c.isActive, isFalse);
    });
  });

  group('CouponDraft.validate', () {
    const ok = CouponDraft(type: 'percent', value: 10);

    test('a plain percent draft passes', () {
      expect(ok.validate(), isNull);
    });

    test('refuses a malformed code but allows a blank one', () {
      expect(
        const CouponDraft(code: 'ab', type: 'percent', value: 10).validate(),
        isNotNull,
      );
      expect(
        const CouponDraft(
          code: 'hello world',
          type: 'percent',
          value: 10,
        ).validate(),
        isNotNull,
      );
      expect(
        const CouponDraft(code: '  ', type: 'percent', value: 10).validate(),
        isNull,
      );
    });

    test('refuses zero, over-100 percent and a limit under one', () {
      expect(
        const CouponDraft(type: 'percent', value: 0).validate(),
        isNotNull,
      );
      expect(
        const CouponDraft(type: 'percent', value: 101).validate(),
        isNotNull,
      );
      expect(const CouponDraft(type: 'flat', value: 101).validate(), isNull);
      expect(
        const CouponDraft(type: 'flat', value: 5, usageLimit: 0).validate(),
        isNotNull,
      );
    });

    test('the end must come after the start', () {
      final d = CouponDraft(
        type: 'percent',
        value: 10,
        validFrom: DateTime(2026, 10, 2),
        validTo: DateTime(2026, 10, 1),
      );
      expect(d.validate(), isNotNull);
    });

    test('every order type, or none, means no rule', () {
      expect(
        const CouponDraft(
          type: 'percent',
          value: 10,
          orderTypes: [],
        ).effectiveOrderTypes,
        isNull,
      );
      expect(
        const CouponDraft(
          type: 'percent',
          value: 10,
          orderTypes: ['dine_in', 'pickup', 'delivery'],
        ).effectiveOrderTypes,
        isNull,
      );
      expect(
        const CouponDraft(
          type: 'percent',
          value: 10,
          orderTypes: ['dine_in'],
        ).effectiveOrderTypes,
        ['dine_in'],
      );
    });

    test('a pause keeps every other field', () {
      final c = Coupon.fromRow({
        'id': 'cp-1',
        'code': 'SAVE10-7KQ2',
        'type': 'percent',
        'value': '10',
        'is_active': true,
        'usage_limit': 5,
        'used_count': 1,
        'min_subtotal_cents': 100,
        'once_per_customer': true,
        'order_types': ['delivery'],
        'created_at': '2026-08-30T10:00:00+00:00',
      });
      final paused = c.toDraft().copyWith(isActive: false);
      expect(paused.id, 'cp-1');
      expect(paused.code, 'SAVE10-7KQ2');
      expect(paused.isActive, isFalse);
      expect(paused.usageLimit, 5);
      expect(paused.minSubtotalCents, 100);
      expect(paused.oncePerCustomer, isTrue);
      expect(paused.orderTypes, ['delivery']);
    });
  });
}
