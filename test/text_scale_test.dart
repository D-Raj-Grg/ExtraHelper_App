import 'package:extrahelper/core/prefs.dart';
import 'package:extrahelper/core/widgets/earlier_day_chip.dart';
import 'package:extrahelper/data/supabase/tenant_repository.dart';
import 'package:extrahelper/data/sync/sync_providers.dart';
import 'package:extrahelper/features/pos/bill_models.dart';
import 'package:extrahelper/features/pos/bill_providers.dart';
import 'package:extrahelper/features/pos/bill_view_screen.dart';
import 'package:extrahelper/features/pos/checkout_screen.dart';
import 'package:extrahelper/features/tenant/tenant_providers.dart';
import 'package:extrahelper/features/welcome/welcome_screen.dart';
import 'package:extrahelper/features/welcome/welcome_slides.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The bill surfaces at double text size on a small phone.
///
/// This app ships to people who turn their text size up, and it is read
/// one-handed mid-service. A row that overflows there does not merely look
/// wrong: Flutter clips it, and the digits it clips are off the right-hand
/// edge — the end of a price. Every one of these started as a real overflow.

const _billId = 'bill-1111-2222-3333-444444444444';

class _FixedSnapshot extends BillSnapshotNotifier {
  _FixedSnapshot(this.value);

  final BillSnapshot value;

  @override
  Future<BillSnapshot> build(String billId) async => value;
}

/// A long dish name, a four-figure price, and two rows that fold into one —
/// the widest thing any of these screens has to draw.
BillSnapshot _snapshot() => BillSnapshot(
  bill: Bill(
    id: _billId,
    status: 'open',
    createdAt: DateTime(2026, 8, 13, 19, 42),
    subtotalCents: 336000,
    taxCents: 43680,
    serviceChargeCents: 33600,
    discountCents: 0,
    tipCents: 0,
    roundingCents: 0,
    totalCents: 413280,
    tableLabel: 'A1',
  ),
  lines: const [
    BillLine(
      id: 'l1',
      orderItemId: 'oi1',
      description: 'Chicken sekuwa platter with extra achar',
      qty: 1,
      unitPriceCents: 168000,
      totalCents: 168000,
    ),
    BillLine(
      id: 'l2',
      orderItemId: 'oi2',
      description: 'Chicken sekuwa platter with extra achar',
      qty: 1,
      unitPriceCents: 168000,
      totalCents: 168000,
    ),
  ],
  payments: const [],
  charges: const [],
  discounts: const [],
  settings: const TenantMoneySettings(),
);

List<Override> _overrides({String role = 'manager'}) => [
  membershipsProvider.overrideWith(
    (ref) => [
      Membership(
        tenantId: 't1',
        name: 'The Sekuwa Station',
        slug: 'sekuwa',
        role: role,
        currency: 'NPR',
        timezone: 'Asia/Kathmandu',
      ),
    ],
  ),
  permissionsProvider.overrideWith(
    (ref) => {'checkout.view', 'payment.take', 'order.discount', 'order.void'},
  ),
  isOnlineProvider.overrideWith((ref) => Stream.value(true)),
  billSnapshotProvider.overrideWith(() => _FixedSnapshot(_snapshot())),
];

Widget _scaled(Widget home, List<Override> overrides) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(
    builder: (context, child) => MediaQuery.withClampedTextScaling(
      minScaleFactor: 2.0,
      maxScaleFactor: 2.0,
      child: child!,
    ),
    home: home,
  ),
);

void _smallPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('the bill view survives a big text size on a small phone', (
    tester,
  ) async {
    _smallPhone(tester);
    await tester.pumpWidget(
      _scaled(const BillViewScreen(billId: _billId), _overrides()),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('the bill view drops its columns rather than clipping a price', (
    tester,
  ) async {
    _smallPhone(tester);
    await tester.pumpWidget(
      _scaled(const BillViewScreen(billId: _billId), _overrides()),
    );
    await tester.pumpAndSettle();

    // Stacked: the table header goes, and quantity and rate move under the
    // name where the checkout card already puts them.
    expect(find.text('Particulars'), findsNothing);
    expect(find.textContaining('2 × '), findsOneWidget);
  });

  testWidgets('checkout survives it too, folded lines and all', (tester) async {
    _smallPhone(tester);
    await tester.pumpWidget(
      _scaled(const CheckoutScreen(billId: _billId), _overrides()),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  // The first thing a new install sees, at the size someone who needs it reads
  // at. The art gives way here rather than pushing the sentence off the screen;
  // what must survive is the sentence.
  testWidgets('the welcome carousel survives it, first slide and last', (
    tester,
  ) async {
    _smallPhone(tester);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      _scaled(const WelcomeScreen(), [
        sharedPreferencesProvider.overrideWith((ref) => prefs),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text(welcomeSlides.first.headline), findsOneWidget);
    expect(tester.takeException(), isNull);

    for (var i = 0; i < welcomeSlides.length - 1; i++) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }

    expect(find.text(welcomeSlides.last.headline), findsOneWidget);
    expect(find.text('Get started'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the carried-over chip wraps instead of running off a card', (
    tester,
  ) async {
    _smallPhone(tester);
    await tester.pumpWidget(
      _scaled(
        Scaffold(
          body: Row(
            children: [
              const Expanded(child: Text('Table A1')),
              // The shape both POS cards use: a status word that can give way,
              // and the chip beside it constrained rather than free to grow.
              Flexible(child: EarlierDayChip(at: DateTime(2026, 8, 13))),
            ],
          ),
        ),
        _overrides(),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
