import 'package:extrahelper/features/pos/cart_bill_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  test('the label says whether a bill already exists', () {
    expect(billButtonLabel(hasBill: false), 'Generate bill');
    expect(billButtonLabel(hasBill: true), 'Finish the bill');
  });

  testWidgets('nothing waiting to be sent: tappable, no warning', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _wrap(
        CartBillButton(
          label: 'Generate bill',
          unsent: false,
          busy: false,
          onPressed: () => taps++,
        ),
      ),
    );

    expect(find.text('Send the new items first.'), findsNothing);
    await tester.tap(find.text('Generate bill'));
    expect(taps, 1);
  });

  testWidgets('unsent lines: disabled, and says why', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _wrap(
        CartBillButton(
          label: 'Finish the bill',
          unsent: true,
          busy: false,
          onPressed: () => taps++,
        ),
      ),
    );

    expect(find.text('Send the new items first.'), findsOneWidget);
    await tester.tap(find.text('Finish the bill'), warnIfMissed: false);
    expect(taps, 0);
  });

  testWidgets('busy: disabled, so a double tap cannot open two bills', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _wrap(
        CartBillButton(
          label: 'Generate bill',
          unsent: false,
          busy: true,
          onPressed: () => taps++,
        ),
      ),
    );

    await tester.tap(find.text('Generate bill'), warnIfMissed: false);
    expect(taps, 0);
  });

  testWidgets('keeps a 44px tap target', (tester) async {
    await tester.pumpWidget(
      _wrap(
        CartBillButton(
          label: 'Generate bill',
          unsent: false,
          busy: false,
          onPressed: () {},
        ),
      ),
    );

    expect(
      tester.getSize(find.byType(OutlinedButton)).height,
      greaterThanOrEqualTo(44),
    );
  });
}
