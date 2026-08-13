import 'package:extrahelper/features/pos/bill_math.dart';
import 'package:extrahelper/features/pos/bill_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// The parity suite.
///
/// Every expectation here is the integer the **web** produces for the same
/// input. These are the only figures checkout computes on the client, so if one
/// of them drifts, the phone quotes a guest a different number than the counter
/// screen does — which is a bill somebody has to argue about at the till.
void main() {
  group('distributeCents', () {
    test('parts sum back to the total exactly', () {
      for (final total in [0, 1, 99, 100, 1001, 123456]) {
        for (final n in [1, 2, 3, 4, 7]) {
          final parts = distributeCents(total, n);
          expect(parts.length, n);
          expect(parts.fold(0, (a, b) => a + b), total);
        }
      }
    });

    test('the remainder goes to the earliest shares', () {
      // 10.01 three ways: 3.34 / 3.34 / 3.33 — never three of 3.33 with a cent
      // quietly lost.
      expect(distributeCents(1001, 3), [334, 334, 333]);
      expect(distributeCents(100, 3), [34, 33, 33]);
    });

    test('degenerate splits', () {
      expect(distributeCents(500, 1), [500]);
      expect(distributeCents(0, 4), [0, 0, 0, 0]);
    });
  });

  group('roundOffCents', () {
    test('rounds the total down to the whole unit', () {
      expect(roundOffCents(totalCents: 12437, roundingCents: 0), -37);
    });

    test('an already-round bill needs no round off', () {
      expect(roundOffCents(totalCents: 12400, roundingCents: 0), 0);
    });

    test('pressing it twice asks for the same round off, not another one', () {
      // 124.37 rounded to 124.00 leaves total 12400 and rounding -37. Asked
      // again it answers -37 — the same value already stored, so a second tap
      // is a no-op rather than shaving another 37 cents off.
      expect(roundOffCents(totalCents: 12400, roundingCents: -37), -37);
    });

    test('never reaches a whole unit, so set_bill_extras will accept it', () {
      for (var total = 0; total < 500; total++) {
        final off = roundOffCents(totalCents: total, roundingCents: 0);
        expect(off.abs() <= 99, isTrue, reason: 'total $total gave $off');
      }
    });
  });

  group('itemShareCents', () {
    test('is proportional to the whole bill, not just the lines', () {
      // Half the lines, on a bill whose total carries tax and service.
      expect(
        itemShareCents(
          selectedSubtotalCents: 5000,
          linesTotalCents: 10000,
          totalCents: 11300,
          dueCents: 11300,
        ),
        5650,
      );
    });

    test('never more than what is still due', () {
      expect(
        itemShareCents(
          selectedSubtotalCents: 10000,
          linesTotalCents: 10000,
          totalCents: 11300,
          dueCents: 200,
        ),
        200,
      );
    });

    test('a bill with no lines has no share to take', () {
      expect(
        itemShareCents(
          selectedSubtotalCents: 0,
          linesTotalCents: 0,
          totalCents: 500,
          dueCents: 500,
        ),
        0,
      );
    });
  });

  group('lineDiscountCents', () {
    DiscountRow pct(num v) => DiscountRow(type: 'percent', value: v);
    DiscountRow flat(num v) => DiscountRow(type: 'flat', value: v);

    test('percent comes off the line', () {
      // 3 × 4.99 = 14.97, 10% → Math.round(149.7) = 150.
      expect(lineDiscountCents(lineGrossCents: 1497, forLine: [pct(10)]), 150);
    });

    test('flat is in whole currency units, not cents', () {
      expect(lineDiscountCents(lineGrossCents: 1497, forLine: [flat(5)]), 500);
    });

    test('a flat discount is capped at the line', () {
      expect(lineDiscountCents(lineGrossCents: 300, forLine: [flat(50)]), 300);
    });

    test('stacked discounts are capped in aggregate', () {
      // A line cannot go negative and hand money back.
      expect(
        lineDiscountCents(lineGrossCents: 1000, forLine: [pct(60), pct(60)]),
        1000,
      );
    });

    test('no discounts is zero, not null', () {
      expect(lineDiscountCents(lineGrossCents: 1000, forLine: const []), 0);
    });
  });

  group('maxRedeemablePoints', () {
    test('capped by the balance and by what is due', () {
      expect(
        maxRedeemablePoints(points: 500, dueCents: 300, pointsValueCents: 1),
        300,
      );
      expect(
        maxRedeemablePoints(points: 120, dueCents: 5000, pointsValueCents: 1),
        120,
      );
    });

    test('a rate above one cent buys fewer points of room', () {
      expect(
        maxRedeemablePoints(points: 500, dueCents: 1000, pointsValueCents: 25),
        40,
      );
    });

    test('an unset points value does not divide by zero', () {
      expect(
        maxRedeemablePoints(points: 500, dueCents: 300, pointsValueCents: 0),
        300,
      );
    });

    test('nothing to redeem against a settled bill', () {
      expect(
        maxRedeemablePoints(points: 500, dueCents: 0, pointsValueCents: 1),
        0,
      );
    });
  });

  group('idempotency keys', () {
    test('the same split slot always yields the same key', () {
      final a = splitKey(billId: 'b1', mode: 'eq', nonce: 'n', slot: 0);
      final b = splitKey(billId: 'b1', mode: 'eq', nonce: 'n', slot: 0);
      expect(a, b);
    });

    test('two shares of equal value still differ, because the slot does', () {
      expect(
        splitKey(billId: 'b1', mode: 'eq', nonce: 'n', slot: 0),
        isNot(splitKey(billId: 'b1', mode: 'eq', nonce: 'n', slot: 1)),
      );
    });

    test('a fresh attempt at splitting is a fresh set of keys', () {
      expect(
        splitKey(billId: 'b1', mode: 'eq', nonce: 'n1', slot: 0),
        isNot(splitKey(billId: 'b1', mode: 'eq', nonce: 'n2', slot: 0)),
      );
    });

    test('the key ring holds one key per amount', () {
      var n = 0;
      final ring = PaymentKeyRing(() => 'k${n++}');

      // A retry of the same payment must reuse the key, or the guest pays twice.
      expect(ring.keyFor(500), 'k0');
      expect(ring.keyFor(500), 'k0');

      // A different amount is a different payment.
      expect(ring.keyFor(600), 'k1');
      expect(ring.keyFor(600), 'k1');

      // Back to 500 after the amount moved: that is a new payment too.
      expect(ring.keyFor(500), 'k2');
    });

    test('clearing means the next payment is a new one', () {
      var n = 0;
      final ring = PaymentKeyRing(() => 'k${n++}');
      expect(ring.keyFor(500), 'k0');
      ring.clear();
      expect(ring.keyFor(500), 'k1');
    });
  });
}
