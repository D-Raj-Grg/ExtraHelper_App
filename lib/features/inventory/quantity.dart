/// Quantities are `numeric` in Postgres and mean nothing without their unit.
///
/// Trailing zeros are noise on a shelf label: 3.750 kg reads as "3.75 kg", and
/// 12.000 as "12". Never `toStringAsFixed` at a call site — a store room list
/// with three different number formats in it is unreadable at arm's length.
String qty(double value, {int decimals = 3}) {
  final fixed = value.toStringAsFixed(decimals);
  if (!fixed.contains('.')) return fixed;
  final trimmed = fixed
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
  return trimmed.isEmpty || trimmed == '-' ? '0' : trimmed;
}

/// A quantity with its unit — "3.75 kg".
String qtyWithUom(double value, String uom) => '${qty(value)} $uom';

/// A signed quantity, for anything that is a *change* rather than a level.
///
/// The sign is the meaning here, so it is always printed — `+2` and `−2` are
/// different facts, and a bare `2` next to a red pixel is not an answer for
/// someone who cannot see the red. Uses a real minus sign, which lines up in
/// tabular figures where a hyphen does not.
String signedQty(double value, String uom) {
  final magnitude = qtyWithUom(value.abs(), uom);
  if (value == 0) return magnitude;
  return value > 0 ? '+$magnitude' : '−$magnitude';
}
