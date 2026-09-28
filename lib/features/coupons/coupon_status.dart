import '../../core/format/labels.dart';
import '../../core/format/money.dart';
import '../../data/supabase/coupons_repository.dart';

/// Pure helpers shared by the list, the form and the QR sheet. Ported from
/// the web's `lib/coupon-constants.ts` so a coupon reads the same on both.

enum CouponStatus { active, paused, scheduled, expired, usedUp }

/// Where a campaign stands right now — the badge on the list.
CouponStatus couponStatus(Coupon c, DateTime now) {
  if (!c.isActive) return CouponStatus.paused;
  final limit = c.usageLimit;
  if (limit != null && c.usedCount >= limit) return CouponStatus.usedUp;
  final to = c.validTo;
  if (to != null && !to.isAfter(now)) return CouponStatus.expired;
  final from = c.validFrom;
  if (from != null && from.isAfter(now)) return CouponStatus.scheduled;
  return CouponStatus.active;
}

String couponStatusLabel(CouponStatus s) => switch (s) {
  CouponStatus.active => 'Active',
  CouponStatus.paused => 'Paused',
  CouponStatus.scheduled => 'Scheduled',
  CouponStatus.expired => 'Expired',
  CouponStatus.usedUp => 'Used up',
};

/// "10% off" / "NPR 200.00 off" — what the coupon is worth, in words.
String couponValueLabel(String type, double value, String currency) =>
    type == 'percent'
    ? '${trimZeros(value)}% off'
    : '${money((value * 100).round(), currency)} off';

String trimZeros(double n) {
  if (n == n.roundToDouble()) return n.toInt().toString();
  return n.toString().replaceAll(RegExp(r'\.?0+$'), '');
}

/// "10% off · min NPR 1,000.00 · dine in only" — the rules on one line.
String couponSummary(Coupon c, String currency) {
  final parts = [couponValueLabel(c.type, c.value, currency)];
  if (c.minSubtotalCents > 0) {
    parts.add('min ${money(c.minSubtotalCents, currency)}');
  }
  final types = c.orderTypes;
  if (types != null &&
      types.isNotEmpty &&
      types.length < couponOrderTypes.length) {
    parts.add(
      '${types.map((t) => orderTypeLabel(t).toLowerCase()).join(' / ')} only',
    );
  }
  if (c.oncePerCustomer) parts.add('once per customer');
  return parts.join(' · ');
}

/// The URL a flyer QR encodes: the storefront with the code pre-filled.
/// Same shape as the web's `couponUrl`, so a QR made here scans on the web
/// checkout and one printed there scans on the phone.
String couponUrl(String origin, String slug, String code) {
  final base = origin.replaceAll(RegExp(r'/+$'), '');
  return '$base/s/${Uri.encodeComponent(slug)}'
      '?coupon=${Uri.encodeComponent(code)}';
}

/// What to put in the QR: the storefront link when the app knows where the
/// storefront is, otherwise the bare code (still scans at the till).
String couponQrPayload({
  required String origin,
  required String slug,
  required String code,
}) => origin.trim().isEmpty || slug.trim().isEmpty
    ? code
    : couponUrl(origin, slug, code);
