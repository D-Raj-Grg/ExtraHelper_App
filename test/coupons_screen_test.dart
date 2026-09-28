import 'package:extrahelper/data/supabase/coupons_repository.dart';
import 'package:extrahelper/data/supabase/tenant_repository.dart';
import 'package:extrahelper/data/sync/sync_providers.dart';
import 'package:extrahelper/features/coupons/coupons_providers.dart';
import 'package:extrahelper/features/coupons/coupons_screen.dart';
import 'package:extrahelper/features/tenant/tenant_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// What the Coupons screen shows, and to whom. `coupons.view` opens the
/// list; `coupons.manage` adds the levers. The server still checks both.

final _flyer = Coupon(
  id: 'cp-1',
  code: 'SAVE10-7KQ2',
  name: 'Dashain flyer',
  type: 'percent',
  value: 10,
  isActive: true,
  createdAt: DateTime(2026, 9, 1),
  usageLimit: 100,
  usedCount: 12,
  redemptions: 12,
  discountGivenCents: 61200,
);

final _paused = Coupon(
  id: 'cp-2',
  code: 'FLAT200',
  type: 'flat',
  value: 200,
  isActive: false,
  createdAt: DateTime(2026, 9, 2),
);

Widget _app({
  required Set<String> permissions,
  List<Coupon> coupons = const [],
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
      couponsProvider.overrideWith((ref) async => coupons),
    ],
    child: MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: '/',
        routes: [GoRoute(path: '/', builder: (_, _) => const CouponsScreen())],
      ),
    ),
  );
}

void main() {
  testWidgets('the list shows each coupon with its badge and usage', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        permissions: const {'coupons.view', 'coupons.manage'},
        coupons: [_flyer, _paused],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('SAVE10-7KQ2'), findsOneWidget);
    expect(find.text('Dashain flyer'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('FLAT200'), findsOneWidget);
    expect(find.text('Paused'), findsOneWidget);
    expect(find.textContaining('Used 12 / 100'), findsOneWidget);
    expect(find.textContaining('Given'), findsOneWidget);
    expect(find.text('New coupon'), findsOneWidget);
  });

  testWidgets('a viewer gets the list and the QR, not the levers', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(permissions: const {'coupons.view'}, coupons: [_flyer]),
    );
    await tester.pumpAndSettle();

    expect(find.text('New coupon'), findsNothing);

    await tester.tap(find.text('SAVE10-7KQ2'));
    await tester.pumpAndSettle();
    expect(find.text('Show QR'), findsOneWidget);
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Delete'), findsNothing);
  });

  testWidgets('a manager is offered pause, edit and delete', (tester) async {
    await tester.pumpWidget(
      _app(
        permissions: const {'coupons.view', 'coupons.manage'},
        coupons: [_flyer],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('SAVE10-7KQ2'));
    await tester.pumpAndSettle();
    expect(find.text('Pause'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);

    // A used coupon cannot go: the dialog offers the pause instead.
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Pause instead'), findsOneWidget);
    expect(find.text('Delete coupon'), findsNothing);
  });

  testWidgets('the empty state teaches the next step', (tester) async {
    await tester.pumpWidget(
      _app(permissions: const {'coupons.view', 'coupons.manage'}),
    );
    await tester.pumpAndSettle();
    expect(find.text('No coupons yet'), findsOneWidget);
    expect(find.textContaining('New coupon'), findsWidgets);
  });

  testWidgets('without coupons.view the screen is a locked door', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(permissions: const {'order.create'}, coupons: [_flyer]),
    );
    await tester.pumpAndSettle();
    expect(find.text('No coupon access'), findsOneWidget);
    expect(find.text('SAVE10-7KQ2'), findsNothing);
  });
}
