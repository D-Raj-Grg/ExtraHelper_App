import 'bill_models.dart';

/// Folding repeated bill lines into one row with a quantity.
///
/// Ported from the web's `groupParticulars` (`lib/print/docs.ts`) so the screen
/// and the paper say the same thing. The server writes one `order_items` row
/// per tap — `amend_order_add_item` inserts unconditionally, and `recompute_bill`
/// copies `order_items` to `bill_items` one for one — so three teas ordered in
/// three rounds are three rows. A guest reading that counts three teas at one
/// price each and thinks they have been charged wrong.
///
/// Grouping is **display only**. Nothing here writes, and every source line
/// keeps its own id, so `apply_item_discount` and `void_order_item` still act
/// on exactly one `order_item_id`.
///
/// One deliberate divergence from the paper: this key also carries the
/// modifiers and whether the line can be adjusted (see [_key]), while
/// `groupParticulars` keys on description and unit price alone. Two drinks at
/// the same price that differ only by a modifier therefore read as two rows
/// here and one row on the slip. The totals still agree — only the breakdown
/// differs — and folding them on screen would put a delete button on a row
/// whose label describes a different drink. The fix belongs on the paper side,
/// in `docs.ts`.
class GroupedBillLine {
  const GroupedBillLine({
    required this.description,
    required this.unitPriceCents,
    required this.qty,
    required this.totalCents,
    required this.discountCents,
    required this.modifiers,
    required this.sources,
  });

  final String description;
  final int unitPriceCents;

  /// Summed across [sources] — the number the guest counts.
  final int qty;
  final int totalCents;
  final int discountCents;

  /// The modifiers every source line shares; they are part of the grouping key,
  /// so all sources carry the same set.
  final List<BillLineModifier> modifiers;

  /// The `bill_items` rows behind this row, in the order the bill lists them.
  /// Always at least one.
  final List<BillLine> sources;

  bool get isGrouped => sources.length > 1;

  /// The single line the per-line sheets can act on, or null when this row
  /// stands for several and the cashier has yet to pick one.
  BillLine? get soleSource => sources.length == 1 ? sources.first : null;

  bool get isAdjustable => sources.first.isAdjustable;
}

/// One row per distinct item, quantities summed, first-seen order preserved.
List<GroupedBillLine> groupBillLines(List<BillLine> lines) {
  final order = <String>[];
  final buckets = <String, List<BillLine>>{};

  for (final line in lines) {
    final key = _key(line);
    final bucket = buckets[key];
    if (bucket == null) {
      order.add(key);
      buckets[key] = [line];
    } else {
      bucket.add(line);
    }
  }

  return [for (final key in order) _fold(buckets[key]!)];
}

GroupedBillLine _fold(List<BillLine> sources) {
  var qty = 0;
  var total = 0;
  var discount = 0;
  for (final line in sources) {
    qty += line.qty;
    total += line.totalCents;
    discount += line.discountCents;
  }
  final first = sources.first;
  return GroupedBillLine(
    description: first.description,
    unitPriceCents: first.unitPriceCents,
    qty: qty,
    totalCents: total,
    discountCents: discount,
    modifiers: first.modifiers,
    sources: sources,
  );
}

/// What makes two lines the same line to a guest.
///
/// Description and unit price are the web's key. Two more join it here:
///
/// * **Modifiers** — "Tea" and "Tea, no sugar" are not the same drink, and the
///   row prints its modifiers underneath. The web gets away without this
///   because its `description` already carries them onto the paper.
/// * **Adjustability** — a line `recompute_bill` wrote with no `order_item_id`
///   behind it can never be discounted or voided. Folding one into a line that
///   can would offer a delete button that acts on a different row than the one
///   the cashier is looking at.
String _key(BillLine line) {
  final mods =
      line.modifiers.map((m) => '${m.id}×${m.qty}').toList(growable: false)
        ..sort();
  return [
    line.description,
    line.unitPriceCents,
    line.isAdjustable,
    mods.join(','),
  ].join('|');
}
