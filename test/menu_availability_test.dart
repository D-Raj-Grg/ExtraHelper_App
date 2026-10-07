import 'package:extrahelper/features/pos/models.dart';
import 'package:flutter_test/flutter_test.dart';

PosMenuItem _item(String id, {bool is86 = false}) => PosMenuItem(
  id: id,
  name: 'Dish $id',
  basePriceCents: 1000,
  categoryId: null,
  is86: is86,
);

void main() {
  test('items default to orderable now', () {
    final item = _item('a');
    expect(item.unavailableNow, isFalse);
    expect(item.availableAgain, isNull);
  });

  test('applyAvailability flags only the listed items and keeps the label', () {
    final out = PosMenuItem.applyAvailability(
      [_item('a'), _item('b'), _item('c')],
      {'b': 'today 18:00', 'c': null},
    );
    expect(out[0].unavailableNow, isFalse);
    expect(out[1].unavailableNow, isTrue);
    expect(out[1].availableAgain, 'today 18:00');
    // Out of window with no future window: still unavailable, no label.
    expect(out[2].unavailableNow, isTrue);
    expect(out[2].availableAgain, isNull);
  });

  test('copyWith(is86) keeps the availability flag', () {
    final flagged = PosMenuItem.applyAvailability(
      [_item('a')],
      {'a': 'tomorrow 11:00'},
    ).single;
    final after = flagged.copyWith(is86: true);
    expect(after.is86, isTrue);
    expect(after.unavailableNow, isTrue);
    expect(after.availableAgain, 'tomorrow 11:00');
  });

  test('empty map clears nothing and flags nothing', () {
    final out = PosMenuItem.applyAvailability([_item('a')], const {});
    expect(out.single.unavailableNow, isFalse);
  });
}
