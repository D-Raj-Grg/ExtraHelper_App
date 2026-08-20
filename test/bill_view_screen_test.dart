import 'package:extrahelper/core/widgets/earlier_day_chip.dart';
import 'package:extrahelper/data/supabase/tenant_repository.dart';
import 'package:extrahelper/data/sync/sync_providers.dart';
import 'package:extrahelper/features/pos/bill_models.dart';
import 'package:extrahelper/features/pos/bill_providers.dart';
import 'package:extrahelper/features/pos/bill_view_screen.dart';
import 'package:extrahelper/features/tenant/tenant_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The bill as a document.
///
/// Two things matter here: it must say the same numbers checkout says, and it
/// must not offer a single control that changes them. A read-only screen that
/// grew a button is how a cashier ends up committing money from the wrong
/// place.

const _billId = 'bill-1111-2222-3333-444444444444';

class _FixedSnapshot extends BillSnapshotNotifier {
  _FixedSnapshot(this.value);

  final BillSnapshot value;

  @override
  Future<BillSnapshot> build(String billId) async => value;
}

BillSnapshot _snapshot({
  String status = 'open',
  DateTime? createdAt,
  List<BillLine>? lines,
}) {
  final items =
      lines ??
      const [
        BillLine(
          id: 'l1',
          orderItemId: 'oi1',
          description: 'Tuborg',
          qty: 1,
          unitPriceCents: 45000,
          totalCents: 45000,
        ),
        BillLine(
          id: 'l2',
          orderItemId: 'oi2',
          description: 'Tuborg',
          qty: 1,
          unitPriceCents: 45000,
          totalCents: 45000,
        ),
      ];
  final total = items.fold(0, (sum, l) => sum + l.totalCents);

  return BillSnapshot(
    bill: Bill(
      id: _billId,
      status: status,
      createdAt: createdAt ?? DateTime(2026, 8, 13, 19, 42),
      subtotalCents: total,
      taxCents: 0,
      serviceChargeCents: 0,
      discountCents: 0,
      tipCents: 0,
      roundingCents: 0,
      totalCents: total,
      tableLabel: 'A1',
    ),
    lines: items,
    payments: const [],
    charges: const [],
    discounts: const [],
    settings: const TenantMoneySettings(),
  );
}

Widget _app(BillSnapshot snapshot, {bool online = true}) => ProviderScope(
  overrides: [
    membershipsProvider.overrideWith(
      (ref) => [
        const Membership(
          tenantId: 't1',
          name: 'The Sekuwa Station',
          slug: 'sekuwa',
          role: 'cashier',
          currency: 'NPR',
          timezone: 'Asia/Kathmandu',
        ),
      ],
    ),
    permissionsProvider.overrideWith((ref) => {'checkout.view'}),
    isOnlineProvider.overrideWith((ref) => Stream.value(online)),
    billSnapshotProvider.overrideWith(() => _FixedSnapshot(snapshot)),
  ],
  child: const MaterialApp(home: BillViewScreen(billId: _billId)),
);

void main() {
  testWidgets('the slip reads as one line of two, not two of one', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_snapshot()));
    await tester.pumpAndSettle();

    expect(find.text('Tuborg'), findsOneWidget);
    // Qty column: the number the guest counts.
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Invoice no: #BILL-111'), findsOneWidget);
  });

  testWidgets('the date is on the document', (tester) async {
    await tester.pumpWidget(_app(_snapshot()));
    await tester.pumpAndSettle();

    expect(find.text('Aug 13, 2026, 7:42 PM'), findsOneWidget);
  });

  testWidgets('a bill carried over from an earlier day says so', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_snapshot()));
    await tester.pumpAndSettle();

    expect(find.byType(EarlierDayChip), findsOneWidget);
    expect(find.text('From Aug 13, 2026'), findsOneWidget);
  });

  testWidgets('a bill opened today carries no carried-over chip', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_snapshot(createdAt: DateTime.now())));
    await tester.pumpAndSettle();

    expect(find.byType(EarlierDayChip), findsNothing);
  });

  testWidgets('nothing on it commits money or changes the bill', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_snapshot()));
    await tester.pumpAndSettle();

    for (final label in const [
      'Take payment',
      'Discounts, charges, tip',
      'Split the check',
      'Add items',
      'Refund',
    ]) {
      expect(find.text(label), findsNothing, reason: '$label is checkout\'s');
    }
    // The one action that belongs: printing reads the bill, it does not change
    // it.
    expect(find.text('Print bill'), findsOneWidget);
  });

  testWidgets('offline, printing is dead rather than absent', (tester) async {
    // Same call as checkout's bar: a missing button reads as "this bill cannot
    // be printed", which is a different and wronger thing than "not now".
    await tester.pumpWidget(_app(_snapshot(), online: false));
    await tester.pumpAndSettle();

    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Print bill'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('a voided bill offers no paper at all', (tester) async {
    await tester.pumpWidget(_app(_snapshot(status: 'void')));
    await tester.pumpAndSettle();

    expect(find.text('Print bill'), findsNothing);
    expect(find.text('Print receipt'), findsNothing);
  });
}
