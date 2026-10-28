import 'package:extrahelper/core/widgets/choice_chip.dart';
import 'package:extrahelper/core/widgets/menu_tile.dart';
import 'package:extrahelper/features/pos/cart_bill_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child, {double width = 190, double textScale = 1}) =>
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: width, child: child),
          ),
        ),
      ),
    );

MenuTile _tile({int qty = 0, String name = 'Water'}) => MenuTile(
  name: name,
  minPriceCents: 3000,
  maxPriceCents: 3000,
  currency: 'NPR',
  onTap: () {},
  qtyInOrder: qty,
);

void main() {
  testWidgets('selected tile carries its 2px border on the Material shape', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(_tile(qty: 1)));
    final material = tester.widget<Material>(
      find.descendant(
        of: find.byType(MenuTile),
        matching: find.byType(Material),
      ),
    );
    final shape = material.shape! as RoundedRectangleBorder;
    expect(shape.side.width, 2);
    expect(shape.side.color, isNot(Colors.transparent));
    expect(material.clipBehavior, Clip.antiAlias);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('tile at the grid height does not overflow with a long name '
      'and 1.5x text', (tester) async {
    const w = 178.0;
    const scale = 1.5;
    await tester.pumpWidget(
      _wrap(
        SizedBox(
          height: w / MenuTile.imageAspect + MenuTile.textBlockHeight * scale,
          child: _tile(name: 'Chicken Chilli Dry with Extra Spicy Sauce'),
        ),
        width: w,
        textScale: scale,
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('dense chip: check when selected, tap area is at least 44', (
    tester,
  ) async {
    var picked = 0;
    await tester.pumpWidget(
      _wrap(
        AppChoiceChip(
          dense: true,
          label: 'Soft Drinks',
          selected: true,
          onSelect: () => picked++,
        ),
        width: 300,
      ),
    );
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(
      tester.getSize(find.byType(InkWell)).height,
      greaterThanOrEqualTo(44),
    );
    await tester.tap(find.text('Soft Drinks'));
    expect(picked, 1);
  });

  testWidgets('bill button can hide its hint', (tester) async {
    await tester.pumpWidget(
      _wrap(
        CartBillButton(
          label: 'Generate bill',
          unsent: true,
          busy: false,
          showHint: false,
          onPressed: () {},
        ),
        width: 300,
      ),
    );
    expect(find.text('Send the new items first.'), findsNothing);
    expect(find.text('Generate bill'), findsOneWidget);
  });
}
