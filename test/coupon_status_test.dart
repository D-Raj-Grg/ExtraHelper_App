import 'package:extrahelper/data/supabase/coupons_repository.dart';
import 'package:extrahelper/features/coupons/coupon_qr_sheet.dart';
import 'package:extrahelper/features/coupons/coupon_status.dart';
import 'package:flutter_test/flutter_test.dart';

Coupon _c({
  bool active = true,
  DateTime? from,
  DateTime? to,
  int? limit,
  int used = 0,
  String type = 'percent',
  double value = 10,
  int min = 0,
  List<String>? types,
  bool once = false,
}) => Coupon(
  id: 'x',
  code: 'SAVE10-7KQ2',
  type: type,
  value: value,
  isActive: active,
  createdAt: DateTime(2026, 9, 1),
  validFrom: from,
  validTo: to,
  usageLimit: limit,
  usedCount: used,
  minSubtotalCents: min,
  orderTypes: types,
  oncePerCustomer: once,
);

void main() {
  final now = DateTime(2026, 9, 28, 12);

  group('couponStatus', () {
    test('the badge matrix matches the web', () {
      expect(couponStatus(_c(), now), CouponStatus.active);
      expect(couponStatus(_c(active: false), now), CouponStatus.paused);
      expect(couponStatus(_c(limit: 3, used: 3), now), CouponStatus.usedUp);
      expect(
        couponStatus(_c(to: DateTime(2026, 9, 28, 12)), now),
        CouponStatus.expired,
      );
      expect(
        couponStatus(_c(from: DateTime(2026, 10, 1)), now),
        CouponStatus.scheduled,
      );
      // Paused wins over everything; used up over expired.
      expect(
        couponStatus(_c(active: false, limit: 1, used: 1), now),
        CouponStatus.paused,
      );
      expect(
        couponStatus(_c(limit: 1, used: 1, to: DateTime(2026, 1, 1)), now),
        CouponStatus.usedUp,
      );
    });
  });

  group('labels', () {
    test('value and summary read like the web', () {
      expect(couponValueLabel('percent', 10, 'NPR'), '10% off');
      expect(couponValueLabel('percent', 12.5, 'NPR'), '12.5% off');
      expect(couponValueLabel('flat', 200, 'NPR'), contains('200.00 off'));
      expect(
        couponSummary(_c(min: 100000, types: ['dine_in'], once: true), 'NPR'),
        allOf(
          startsWith('10% off · min '),
          contains('1,000.00'),
          contains('dine in only'),
          endsWith('once per customer'),
        ),
      );
      // Every type ticked is no rule at all.
      expect(
        couponSummary(_c(types: ['dine_in', 'pickup', 'delivery']), 'NPR'),
        '10% off',
      );
    });
  });

  group('couponUrl', () {
    test('encodes the storefront link, or the bare code without one', () {
      expect(
        couponUrl('https://app.example.com/', 'sekuwa station', 'SAVE10-7KQ2'),
        'https://app.example.com/s/sekuwa%20station?coupon=SAVE10-7KQ2',
      );
      expect(
        couponQrPayload(origin: '', slug: 'sekuwa', code: 'SAVE10-7KQ2'),
        'SAVE10-7KQ2',
      );
      expect(
        couponQrPayload(
          origin: 'https://app.example.com',
          slug: 'sekuwa',
          code: 'SAVE10-7KQ2',
        ),
        'https://app.example.com/s/sekuwa?coupon=SAVE10-7KQ2',
      );
    });
  });

  group('qrModules', () {
    test('encodes a square grid with the finder pattern in the corner', () {
      final grid = qrModules('https://app.example.com/s/sekuwa?coupon=SAVE10');
      expect(grid, isNotEmpty);
      expect(grid.length, grid.first.length);
      // Top-left finder: a 7×7 ring whose outer row is all dark.
      expect(grid[0].take(7).every((b) => b), isTrue);
      expect(grid[1][1], isFalse);
    });
  });

  group('day bounds', () {
    test('the stored exclusive end shows as the day before, and back', () {
      // Stored as local midnight starting Oct 1 → works through Sep 30.
      final stored = DateTime(2026, 10, 1);
      expect(lastDayOf(stored), DateTime(2026, 9, 30));
      expect(exclusiveEndOf(DateTime(2026, 9, 30)), stored);
      // Calendar arithmetic across a month end and a year end.
      expect(lastDayOf(DateTime(2027, 1, 1)), DateTime(2026, 12, 31));
      expect(exclusiveEndOf(DateTime(2026, 12, 31)), DateTime(2027, 1, 1));
    });
  });
}
