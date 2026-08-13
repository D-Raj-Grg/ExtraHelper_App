/// The arithmetic checkout does on the client, and nothing else.
///
/// Every one of these is a port of a figure the web already computes, and each
/// is kept here — pure, no Riverpod, no widgets — so a test can pin it against
/// the exact integer the web produces. A total that differs by one cent between
/// the counter screen and the phone is a bill the guest can argue with.
///
/// **Nothing here decides what is owed.** `recompute_bill` runs inside every
/// mutating RPC and its `total_cents` is the only figure that settles a bill.
/// These are for display, for splitting a known total, and for capping what the
/// UI is allowed to ask for.
///
/// One note on rounding: JavaScript's `Math.round` rounds a half *up* (toward
/// positive infinity) and Dart's `num.round` rounds a half *away from zero*.
/// Every value below is non-negative before rounding, where the two agree.
library;

import 'bill_models.dart';

/// Split [total] cents into [n] parts that sum back to [total] exactly.
///
/// Port of `components/bill-split.tsx` `distribute()`. The remainder goes to the
/// earliest shares, so three ways of 10.01 is 3.34 / 3.34 / 3.33 — never
/// 3.33 × 3 with a cent quietly lost.
List<int> distributeCents(int total, int n) {
  if (n <= 1) return [total];
  final base = total ~/ n;
  final remainder = total - base * n;
  return [for (var i = 0; i < n; i++) base + (i < remainder ? 1 : 0)];
}

/// The round-off that would take this bill down to a whole currency unit.
///
/// Port of `components/checkout/totals-panel.tsx`. Computed against the total
/// *before* any rounding already applied, so pressing it twice is idempotent
/// and a bill already round answers 0 — which is also how "Undo round off"
/// works: send 0.
///
/// Always in `(-100, 0]`, which is what `set_bill_extras` will accept.
int roundOffCents({required int totalCents, required int roundingCents}) {
  final roundable = (totalCents - roundingCents) % 100;
  return roundable == 0 ? 0 : -roundable;
}

/// A payer's proportional share of the **whole** bill — tax, service and
/// discount included — for the lines they picked.
///
/// Port of `components/bill-split.tsx`. Clamped to what is still due, so the
/// last payer absorbs the rounding rather than overpaying into a clamp.
int itemShareCents({
  required int selectedSubtotalCents,
  required int linesTotalCents,
  required int totalCents,
  required int dueCents,
}) {
  if (linesTotalCents <= 0) return 0;
  final share = (selectedSubtotalCents / linesTotalCents * totalCents).round();
  return share < dueCents ? share : dueCents;
}

/// What has already been taken off one line, for display beside it.
///
/// Port of `app/(app)/bill/[billId]/page.tsx`, which in turn mirrors the
/// server's `bill_discount_total`: a percent comes off the line, a flat amount
/// is capped at the line, and the sum is capped at the line as well — a line
/// cannot go negative and hand money back.
int lineDiscountCents({
  required int lineGrossCents,
  required Iterable<DiscountRow> forLine,
}) {
  var sum = 0;
  for (final d in forLine) {
    sum += d.isPercent
        ? (lineGrossCents * d.value / 100).round()
        : _min((d.value * 100).round(), lineGrossCents);
  }
  return _min(sum, lineGrossCents);
}

/// The most points this customer can burn against this bill.
///
/// Port of `components/bill-loyalty.tsx`. The rate is clamped to at least one
/// cent per point: a tenant that never set `points_value_cents` would otherwise
/// divide by zero. The server caps this again inside `redeem_points_for_bill`.
int maxRedeemablePoints({
  required int points,
  required int dueCents,
  required int pointsValueCents,
}) {
  final rate = pointsValueCents < 1 ? 1 : pointsValueCents;
  final affordable = dueCents ~/ rate;
  final capped = _min(points, affordable);
  return capped < 0 ? 0 : capped;
}

/// The idempotency key for one slot of a split.
///
/// Deterministic on purpose: a double-tap on the *same* share sends the same
/// key and `record_payment` dedups it on `unique(tenant_id, idempotency_key)`,
/// while two genuinely separate shares of equal value still differ because
/// their slot does. The nonce separates one attempt at splitting from the next.
///
/// Port of the three key shapes in `components/bill-split.tsx`.
String splitKey({
  required String billId,
  required String mode,
  required String nonce,
  required int slot,
}) => '$billId:$mode:$nonce:$slot';

/// Holds one idempotency key per amount for the single-payment path.
///
/// The rule, from `checkout-view.tsx`: a cashier who retries a payment that
/// timed out must reuse the key, or the guest pays twice — but changing the
/// amount is a different payment and must get a fresh one. [clear] is called
/// once a payment is known to have landed.
class PaymentKeyRing {
  PaymentKeyRing(this._mint);

  /// Injected so a test can pin the keys. Production passes `Uuid().v4`.
  final String Function() _mint;

  String? _key;
  int? _cents;

  /// The key for [cents] — the same one as last time if the amount hasn't
  /// moved. Never call this from a `build`: a fresh key per rebuild is exactly
  /// the double-charge this class exists to stop.
  String keyFor(int cents) {
    if (_key == null || _cents != cents) {
      _key = _mint();
      _cents = cents;
    }
    return _key!;
  }

  /// The payment landed. The next one is a new payment, even for the same
  /// amount.
  void clear() {
    _key = null;
    _cents = null;
  }
}

int _min(int a, int b) => a < b ? a : b;
