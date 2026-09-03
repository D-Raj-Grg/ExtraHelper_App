import 'dart:io';
import 'dart:ui' as ui;

import 'package:extrahelper/core/widgets/earlier_day_chip.dart';
import 'package:extrahelper/data/supabase/tenant_repository.dart';
import 'package:extrahelper/data/sync/sync_providers.dart';
import 'package:extrahelper/features/pos/bill_export.dart';
import 'package:extrahelper/features/pos/bill_models.dart';
import 'package:extrahelper/features/pos/bill_providers.dart';
import 'package:extrahelper/features/pos/bill_view_screen.dart';
import 'package:extrahelper/features/tenant/tenant_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

Widget _app(BillSnapshot snapshot, {bool online = true, FileSharer? sharer}) =>
    ProviderScope(
      overrides: [
        if (sharer != null) fileSharerProvider.overrideWithValue(sharer),
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
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  // The receipt is written to the cache directory before it is shared, and
  // there is no platform under a widget test to say where that is.
  late Directory tempRoot;
  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('bill-view-test');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async =>
          call.method == 'getTemporaryDirectory' ? tempRoot.path : null,
    );
  });
  tearDown(() async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    if (tempRoot.existsSync()) await tempRoot.delete(recursive: true);
  });

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

  group('sending the receipt', () {
    testWidgets('the whole document goes out, not the part that fits', (
      tester,
    ) async {
      // Fifty lines is taller than any phone. The point of the off-screen host
      // is that a viewport never gets to decide what was captured — an in-tree
      // boundary inside the list would hand a guest the visible third of their
      // bill, or throw.
      final requests = <ShareRequest>[];
      await tester.pumpWidget(
        _app(
          _snapshot(lines: _manyLines(50)),
          sharer: (req) async {
            requests.add(req);
            return true;
          },
        ),
      );
      await tester.pumpAndSettle();

      await _tapShare(tester, requests);
      expect(requests, hasLength(1), reason: 'one tap, one share');

      late ui.Image decoded;
      await tester.runAsync(() async {
        decoded = await decodeImageFromList(
          await File(requests.single.file.path).readAsBytes(),
        );
      });

      // The test window is 800×600. A picture several times taller than it is
      // wide can only have come from a document that was never on screen.
      expect(decoded.height, greaterThan(decoded.width * 4));
      expect(
        decoded.height,
        lessThanOrEqualTo(kBillExportMaxPx.round()),
        reason: 'a long bill loses sharpness rather than a texture allocation',
      );
      decoded.dispose();
    });

    testWidgets('a bill that fits goes out at full sharpness', (tester) async {
      final requests = <ShareRequest>[];
      await tester.pumpWidget(
        _app(
          _snapshot(),
          sharer: (req) async {
            requests.add(req);
            return true;
          },
        ),
      );
      await tester.pumpAndSettle();
      await _tapShare(tester, requests);

      late ui.Image decoded;
      await tester.runAsync(() async {
        decoded = await decodeImageFromList(
          await File(requests.single.file.path).readAsBytes(),
        );
      });

      // 380 logical × 3 — sharp enough that a payment QR photographed off the
      // picture still scans.
      expect(decoded.width, kBillExportTargetPx.round());
      decoded.dispose();
    });

    testWidgets('the picture is named for the invoice a guest would quote', (
      tester,
    ) async {
      final requests = <ShareRequest>[];
      await tester.pumpWidget(
        _app(
          _snapshot(),
          sharer: (req) async {
            requests.add(req);
            return true;
          },
        ),
      );
      await tester.pumpAndSettle();

      await _tapShare(tester, requests);

      expect(requests, hasLength(1));
      final req = requests.single;
      expect(req.file.path, contains('receipt-BILL-111-'));
      expect(req.text, contains('#BILL-111'));
      // Null here is what leaves the iPad share sheet pointing at nothing.
      expect(req.origin.width, greaterThan(0));
    });

    testWidgets('offline it still sends — the picture needs no network', (
      tester,
    ) async {
      final requests = <ShareRequest>[];
      await tester.pumpWidget(
        _app(
          _snapshot(),
          online: false,
          sharer: (req) async {
            requests.add(req);
            return true;
          },
        ),
      );
      await tester.pumpAndSettle();

      final button = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.ios_share),
      );
      expect(
        button.onPressed,
        isNotNull,
        reason: 'unlike printing, this is made on the device',
      );
    });

    testWidgets('a voided bill can still be sent as evidence', (tester) async {
      await tester.pumpWidget(_app(_snapshot(status: 'void')));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.ios_share), findsOneWidget);
    });
  });
}

/// Tap Share and let it finish.
///
/// Alternating `pump` and `runAsync` is the whole trick: the frames the capture
/// waits on only happen under `pump`, and `toImage` plus writing the file only
/// happen under `runAsync`, which is where real async is allowed.
Future<void> _tapShare(WidgetTester tester, List<ShareRequest> requests) async {
  await tester.tap(find.byIcon(Icons.ios_share));
  // Generous: rasterising and PNG-encoding a long document takes real time, and
  // more of it when the whole suite is running at once.
  for (var i = 0; i < 300 && requests.isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
}

List<BillLine> _manyLines(int count) => [
  for (var i = 0; i < count; i++)
    BillLine(
      id: 'l$i',
      orderItemId: 'oi$i',
      description: 'Item $i',
      qty: 1,
      unitPriceCents: 1000 + i,
      totalCents: 1000 + i,
    ),
];
