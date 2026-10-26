import 'package:extrahelper/data/supabase/reservations_repository.dart';
import 'package:extrahelper/data/supabase/tenant_repository.dart';
import 'package:extrahelper/data/sync/sync_providers.dart';
import 'package:extrahelper/features/reservations/reservations_providers.dart';
import 'package:extrahelper/features/reservations/reservations_screen.dart';
import 'package:extrahelper/features/tenant/tenant_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

final _now = DateTime.now();
final _today = DateTime(_now.year, _now.month, _now.day, 19);

final _pending = Reservation(
  id: 'r1',
  guestName: 'Asha Rai',
  partySize: 4,
  reservedAt: _today,
  status: ReservationStatus.pending,
  tableLabel: 'T5',
  notes: 'Window seat',
);
final _confirmed = Reservation(
  id: 'r2',
  guestName: 'Bikash Thapa',
  partySize: 2,
  reservedAt: _today.add(const Duration(days: 1)),
  status: ReservationStatus.confirmed,
);
final _cancelled = Reservation(
  id: 'r3',
  guestName: 'Cara Lee',
  partySize: 6,
  reservedAt: _today.add(const Duration(hours: 1)),
  status: ReservationStatus.cancelled,
);

Widget _app({
  required Set<String> permissions,
  String role = 'waiter',
  Future<List<Reservation>> Function()? load,
}) {
  return ProviderScope(
    overrides: [
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
      permissionsProvider.overrideWith((ref) => permissions),
      isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      reservationsProvider.overrideWith((ref) => (load ?? () async => [])()),
    ],
    child: MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(path: '/', builder: (_, _) => const ReservationsScreen()),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets('groups by day with covers, status and actions', (tester) async {
    await tester.pumpWidget(
      _app(
        permissions: const {'reservations.view', 'reservations.edit'},
        load: () async => [_pending, _cancelled, _confirmed],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Tomorrow'), findsOneWidget);
    // Cancelled party of 6 is not a cover.
    expect(find.text('4 covers'), findsOneWidget);
    expect(find.text('2 covers'), findsOneWidget);
    expect(find.text('Asha Rai'), findsOneWidget);
    expect(find.text('Window seat'), findsOneWidget);
    expect(find.textContaining('Table T5'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Confirm'), findsOneWidget);
    expect(find.text('Seat'), findsOneWidget);
    expect(find.text('No-show'), findsWidgets);
    expect(find.text('New reservation'), findsOneWidget);
  });

  testWidgets('cancel asks first', (tester) async {
    await tester.pumpWidget(
      _app(
        permissions: const {'reservations.view', 'reservations.edit'},
        load: () async => [_pending],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Cancel reservation?'), findsOneWidget);
  });

  testWidgets('a viewer sees bookings but no levers', (tester) async {
    await tester.pumpWidget(
      _app(
        permissions: const {'reservations.view'},
        load: () async => [_pending],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Asha Rai'), findsOneWidget);
    expect(find.text('Confirm'), findsNothing);
    expect(find.text('Cancel'), findsNothing);
    expect(find.text('New reservation'), findsNothing);
  });

  testWidgets('a manager gets the levers without the edit key', (tester) async {
    await tester.pumpWidget(
      _app(
        permissions: const {'reservations.view'},
        role: 'manager',
        load: () async => [_pending],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Confirm'), findsOneWidget);
    expect(find.text('New reservation'), findsOneWidget);
  });

  testWidgets('empty state', (tester) async {
    await tester.pumpWidget(_app(permissions: const {'reservations.view'}));
    await tester.pumpAndSettle();
    expect(find.text('No upcoming reservations'), findsOneWidget);
  });

  testWidgets('loading state', (tester) async {
    await tester.pumpWidget(
      _app(
        permissions: const {'reservations.view'},
        load: () => Future<List<Reservation>>.delayed(
          const Duration(seconds: 5),
          () => [],
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    await tester.pumpAndSettle(const Duration(seconds: 6));
  });

  testWidgets('error state offers retry', (tester) async {
    await tester.pumpWidget(
      _app(
        permissions: const {'reservations.view'},
        load: () async => throw Exception('boom'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text("Couldn't load reservations."), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('without reservations.view the screen is a locked door', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(permissions: const {'order.create'}, load: () async => [_pending]),
    );
    await tester.pumpAndSettle();
    expect(find.text('No reservation access'), findsOneWidget);
    expect(find.text('Asha Rai'), findsNothing);
  });
}
