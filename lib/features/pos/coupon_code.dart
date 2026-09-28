/// The code inside whatever was scanned or typed.
///
/// A flyer QR encodes the storefront link with `?coupon=CODE` (so a guest who
/// scans it lands on the menu); the same square held up at the counter has to
/// give the cashier the bare code. Parsing only — whether the code is valid is
/// `apply_coupon`'s call, never this file's (CLAUDE.md rule 1). Mirrors
/// `extractCouponCode` in `extrahelper/lib/coupon-constants.ts`.
///
/// Returns null when there is nothing that looks like a code, so the caller
/// can say "that's not a coupon" instead of sending junk to the server.
String? extractCouponCode(String? raw) {
  final text = (raw ?? '').trim();
  if (text.isEmpty) return null;

  var candidate = text;
  if (RegExp(r'^https?://', caseSensitive: false).hasMatch(text)) {
    final uri = Uri.tryParse(text);
    candidate = uri?.queryParameters['coupon'] ?? '';
  }

  final code = candidate.trim().toUpperCase();
  return _shape.hasMatch(code) ? code : null;
}

/// Same shape as the database check constraint on `coupons.code`.
final RegExp _shape = RegExp(r'^[A-Z0-9-]{4,24}$');
