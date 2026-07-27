import 'package:intl/intl.dart';

/// Currency formatting. Ported from the web's `lib/format.ts` so both clients
/// render a price identically.
///
/// Locale is pinned to `en_US`, matching the web (which pins it to avoid an SSR
/// hydration mismatch). Full locale-awareness is a later i18n task; what
/// matters here is that a bill on the phone and the same bill on the counter
/// screen read the same.
///
/// Currency is always the tenant's code from `tenant_settings` — never
/// hardcoded (rule 2).
String money(int cents, String currency) {
  try {
    final format = NumberFormat.currency(
      locale: 'en_US',
      name: currency,
      symbol: _symbolFor(currency),
    );
    return format.format(cents / 100);
  } catch (_) {
    return '${(cents / 100).toStringAsFixed(2)} $currency';
  }
}

/// A span of prices — "NPR 1,080.00 – 1,680.00" — collapsing to a single price
/// when the ends match.
///
/// Built on [money] so the pinned locale carries over. The currency prefix is
/// printed once: on a tile read at arm's length, repeating it costs lines of
/// wrap for no information.
String moneyRange(int minCents, int maxCents, String currency) {
  if (minCents == maxCents) return money(minCents, currency);
  final lo = money(minCents, currency);
  final hi = money(maxCents, currency);

  final prefixMatch = RegExp(r'^\D+').firstMatch(hi);
  final prefix = prefixMatch?.group(0) ?? '';
  // En dash: this is a range, not a subtraction.
  if (prefix.isNotEmpty && lo.startsWith(prefix)) {
    return '$lo – ${hi.substring(prefix.length)}';
  }
  return '$lo – $hi';
}

/// Symbols for currencies where the bare code reads badly. Anything not listed
/// falls back to the code itself, which is correct for a multi-tenant app that
/// must not assume a country.
String _symbolFor(String currency) {
  const symbols = {'USD': r'$', 'EUR': '€', 'GBP': '£', 'JPY': '¥'};
  return symbols[currency.toUpperCase()] ?? '${currency.toUpperCase()} ';
}
