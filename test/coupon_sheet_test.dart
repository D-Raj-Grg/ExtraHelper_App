import 'package:extrahelper/data/supabase/coupons_repository.dart';
import 'package:extrahelper/features/coupons/coupon_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The form hands back what was typed — and, for an edit, what was *not*
/// touched goes back exactly as it came. The stored dates are instants in
/// the tenant's zone; re-deriving them on a phone in another zone would
/// move the coupon's end.

Widget _host({Coupon? editing, required ValueChanged<CouponDraft?> onDone}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: FilledButton(
            onPressed: () async {
              final d = await showCouponSheet(
                context,
                currency: 'NPR',
                editing: editing,
              );
              onDone(d);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('a new coupon defaults to 10% off, active, no rules', (
    tester,
  ) async {
    CouponDraft? out;
    await tester.pumpWidget(_host(onDone: (d) => out = d));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('New coupon'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Campaign'), 'Flyer');
    await tester.ensureVisible(find.text('Create coupon'));
    await tester.tap(find.text('Create coupon'));
    await tester.pumpAndSettle();

    expect(out, isNotNull);
    expect(out!.id, isNull);
    expect(out!.code, isEmpty);
    expect(out!.name, 'Flyer');
    expect(out!.type, 'percent');
    expect(out!.value, 10);
    expect(out!.isActive, isTrue);
    expect(out!.validFrom, isNull);
    expect(out!.validTo, isNull);
    expect(out!.effectiveOrderTypes, isNull);
  });

  testWidgets('an edit that never touched the dates returns them unchanged', (
    tester,
  ) async {
    // Instants a web client in Kathmandu would have stored; the test runner
    // is in some other zone, which is the point.
    final from = DateTime.utc(2026, 8, 31, 18, 15);
    final to = DateTime.utc(2026, 9, 30, 18, 15);
    final editing = Coupon(
      id: 'cp-1',
      code: 'SAVE10-7KQ2',
      name: 'Dashain',
      type: 'percent',
      value: 10,
      isActive: true,
      createdAt: DateTime(2026, 8, 1),
      validFrom: from,
      validTo: to,
      redemptions: 3,
    );
    CouponDraft? out;
    await tester.pumpWidget(_host(editing: editing, onDone: (d) => out = d));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Edit coupon'), findsOneWidget);
    // Redeemed: the code field is there but locked.
    final code = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Code'),
    );
    expect(code.readOnly, isTrue);

    await tester.enterText(
      find.widgetWithText(TextField, 'Campaign'),
      'Dashain flyer',
    );
    await tester.ensureVisible(find.text('Save coupon'));
    await tester.tap(find.text('Save coupon'));
    await tester.pumpAndSettle();

    expect(out, isNotNull);
    expect(out!.id, 'cp-1');
    expect(out!.name, 'Dashain flyer');
    expect(out!.validFrom, from);
    expect(out!.validTo, to);
  });

  testWidgets('clearing a date sends null for it', (tester) async {
    final editing = Coupon(
      id: 'cp-1',
      code: 'SAVE10-7KQ2',
      type: 'percent',
      value: 10,
      isActive: true,
      createdAt: DateTime(2026, 8, 1),
      validTo: DateTime.utc(2026, 9, 30, 18, 15),
    );
    CouponDraft? out;
    await tester.pumpWidget(_host(editing: editing, onDone: (d) => out = d));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byTooltip('Clear Through'));
    await tester.tap(find.byTooltip('Clear Through'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save coupon'));
    await tester.tap(find.text('Save coupon'));
    await tester.pumpAndSettle();

    expect(out, isNotNull);
    expect(out!.validTo, isNull);
  });
}
