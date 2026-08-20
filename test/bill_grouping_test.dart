import 'package:extrahelper/features/pos/bill_grouping.dart';
import 'package:extrahelper/features/pos/bill_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Folding repeated lines is a reading aid, not an edit — so the sums have to
/// be exact and the things that make two items genuinely different have to
/// keep them apart. A wrong merge here shows a guest a quantity they did not
/// order, or points a delete button at a row nobody was looking at.

BillLine _line({
  required String id,
  String description = 'Tuborg',
  int qty = 1,
  int unitPriceCents = 45000,
  int? totalCents,
  int discountCents = 0,
  bool adjustable = true,
  List<BillLineModifier> modifiers = const [],
}) => BillLine(
  id: id,
  orderItemId: adjustable ? 'oi-$id' : null,
  description: description,
  qty: qty,
  unitPriceCents: unitPriceCents,
  totalCents: totalCents ?? unitPriceCents * qty,
  discountCents: discountCents,
  modifiers: modifiers,
);

void main() {
  test('the same drink rung up twice reads as one line of two', () {
    final rows = groupBillLines([_line(id: 'a'), _line(id: 'b')]);

    expect(rows, hasLength(1));
    expect(rows.single.description, 'Tuborg');
    expect(rows.single.qty, 2);
    expect(rows.single.totalCents, 90000);
    expect(rows.single.isGrouped, isTrue);
    expect(rows.single.sources.map((l) => l.id), ['a', 'b']);
    // The row stands for two `bill_items`, so no single one can be adjusted
    // without asking which.
    expect(rows.single.soleSource, isNull);
  });

  test('quantities and discounts sum across the rows behind a group', () {
    final rows = groupBillLines([
      _line(id: 'a', qty: 2, discountCents: 5000),
      _line(id: 'b', qty: 3, discountCents: 1000),
    ]);

    expect(rows.single.qty, 5);
    expect(rows.single.totalCents, 45000 * 5);
    expect(rows.single.discountCents, 6000);
  });

  test('a different price is a different line', () {
    final rows = groupBillLines([
      _line(id: 'a'),
      _line(id: 'b', unitPriceCents: 50000),
    ]);

    expect(rows, hasLength(2));
    expect(rows.every((r) => r.qty == 1), isTrue);
  });

  test('a different modifier is a different drink', () {
    const noIce = BillLineModifier(
      id: 'm1',
      name: 'No ice',
      priceCents: 0,
      qty: 1,
    );
    final rows = groupBillLines([
      _line(id: 'a'),
      _line(id: 'b', modifiers: const [noIce]),
    ]);

    expect(rows, hasLength(2));
    expect(rows.last.modifiers.single.name, 'No ice');
  });

  test('a line with no order item behind it never folds into one that has', () {
    final rows = groupBillLines([
      _line(id: 'a'),
      _line(id: 'b', adjustable: false),
    ]);

    expect(rows, hasLength(2));
    expect(rows.first.isAdjustable, isTrue);
    expect(rows.last.isAdjustable, isFalse);
  });

  test('first-seen order is kept, so the bill still reads top to bottom', () {
    final rows = groupBillLines([
      _line(id: 'a', description: 'Dal bhat'),
      _line(id: 'b'),
      _line(id: 'c', description: 'Dal bhat'),
    ]);

    expect(rows.map((r) => r.description), ['Dal bhat', 'Tuborg']);
    expect(rows.first.qty, 2);
  });

  test('an empty bill groups to nothing', () {
    expect(groupBillLines(const []), isEmpty);
  });

  test('a single line keeps its source, so a tap acts straight away', () {
    final rows = groupBillLines([_line(id: 'a')]);

    expect(rows.single.isGrouped, isFalse);
    expect(rows.single.soleSource?.id, 'a');
  });
}
