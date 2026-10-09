import 'package:extrahelper/data/supabase/coupon_batches_repository.dart';
import 'package:extrahelper/data/supabase/tenant_repository.dart';
import 'package:extrahelper/data/sync/sync_providers.dart';
import 'package:extrahelper/features/coupons/coupons_providers.dart';
import 'package:extrahelper/features/coupons/coupons_screen.dart';
import 'package:extrahelper/features/coupons/run_codes_sheet.dart';
import 'package:extrahelper/features/tenant/tenant_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// The Flyers tab: runs for everyone with `coupons.view`, levers for
/// `coupons.manage`. The server still checks both.

final _run = CouponBatch(
  id: 'b1',
  name: 'Dashain flyers',
  type: 'percent',
  value: 10,
  createdAt: DateTime(2026, 10, 1),
  issued: 100,
  redeemed: 7,
  active: 100,
  shared: 40,
);

Widget _app({
  required Set<String> permissions,
  List<CouponBatch> runs = const [],
  CouponStats stats = const CouponStats(),
}) {
  return ProviderScope(
    overrides: [
      membershipsProvider.overrideWith(
        (ref) => [
          Membership(
            tenantId: 't1',
            name: 'The Sekuwa Station',
            slug: 'sekuwa',
            role: 'manager',
            currency: 'NPR',
            timezone: 'Asia/Kathmandu',
          ),
        ],
      ),
      permissionsProvider.overrideWith((ref) => permissions),
      isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      couponsProvider.overrideWith((ref) async => const []),
      couponStatsProvider.overrideWith((ref) async => stats),
      couponBatchesProvider.overrideWith((ref) async => runs),
      batchCodesProvider('b1').overrideWith(
        (ref) async => const [
          BatchCode(
            code: 'DASH-AAAAAA',
            redeemed: true,
            isActive: true,
            shared: true,
          ),
          BatchCode(
            code: 'DASH-BBBBBB',
            redeemed: false,
            isActive: true,
            shared: true,
          ),
          BatchCode(
            code: 'DASH-CCCCCC',
            redeemed: false,
            isActive: true,
            shared: false,
          ),
        ],
      ),
    ],
    child: MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: '/',
        routes: [GoRoute(path: '/', builder: (_, _) => const CouponsScreen())],
      ),
    ),
  );
}

Future<void> _openFlyers(WidgetTester tester) async {
  await tester.tap(find.text('Flyers'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the Flyers tab lists runs with their counts', (tester) async {
    await tester.pumpWidget(
      _app(permissions: const {'coupons.view'}, runs: [_run]),
    );
    await tester.pumpAndSettle();
    await _openFlyers(tester);

    expect(find.text('Dashain flyers'), findsOneWidget);
    expect(find.textContaining('100 made'), findsOneWidget);
    expect(find.textContaining('40 handed out'), findsOneWidget);
    expect(find.textContaining('7 used'), findsOneWidget);
    expect(find.text('Running'), findsOneWidget);
    // A viewer gets no New run lever.
    expect(find.text('New run'), findsNothing);
  });

  testWidgets('a manager sees New run, and pause / edit on a run', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(permissions: const {'coupons.view', 'coupons.manage'}, runs: [_run]),
    );
    await tester.pumpAndSettle();
    await _openFlyers(tester);
    expect(find.text('New run'), findsOneWidget);

    await tester.tap(find.text('Dashain flyers'));
    await tester.pumpAndSettle();
    expect(find.text('Codes'), findsOneWidget);
    expect(find.text('Pause run'), findsOneWidget);
    expect(find.text('Edit name & dates'), findsOneWidget);
  });

  testWidgets('a viewer opening a run sees Codes only', (tester) async {
    await tester.pumpWidget(
      _app(permissions: const {'coupons.view'}, runs: [_run]),
    );
    await tester.pumpAndSettle();
    await _openFlyers(tester);
    await tester.tap(find.text('Dashain flyers'));
    await tester.pumpAndSettle();
    expect(find.text('Codes'), findsOneWidget);
    expect(find.text('Pause run'), findsNothing);
    expect(find.text('Edit name & dates'), findsNothing);
  });

  testWidgets('the empty state teaches the next step', (tester) async {
    await tester.pumpWidget(
      _app(permissions: const {'coupons.view', 'coupons.manage'}),
    );
    await tester.pumpAndSettle();
    await _openFlyers(tester);
    expect(find.text('No flyer runs yet'), findsOneWidget);
    expect(find.textContaining('New run'), findsWidgets);
  });

  testWidgets('the codes sheet names each code\'s state in words', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(permissions: const {'coupons.view', 'coupons.manage'}, runs: [_run]),
    );
    await tester.pumpAndSettle();
    await _openFlyers(tester);
    await tester.tap(find.text('Dashain flyers'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Codes'));
    await tester.pumpAndSettle();

    expect(find.text('DASH-AAAAAA'), findsOneWidget);
    expect(find.text('Used'), findsOneWidget);
    expect(find.text('Handed out'), findsOneWidget);
    expect(find.text('Free'), findsOneWidget);
  });

  testWidgets('the stats strip shows on the Coupons tab', (tester) async {
    await tester.pumpWidget(
      _app(
        permissions: const {'coupons.view'},
        stats: const CouponStats(
          active: 3,
          paused: 1,
          redemptions: 12,
          discountGivenCents: 61200,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Given away'), findsOneWidget);
    expect(find.text('Redemptions'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
  });

  test('codesCsv is one code and its state per line', () {
    const codes = [
      BatchCode(code: 'A-1', redeemed: true, isActive: true, shared: true),
      BatchCode(code: 'A-2', redeemed: false, isActive: false, shared: false),
      BatchCode(code: 'A-3', redeemed: false, isActive: true, shared: false),
    ];
    expect(codesCsv(codes), 'code,status\nA-1,Used\nA-2,Paused\nA-3,Free\n');
  });
}
