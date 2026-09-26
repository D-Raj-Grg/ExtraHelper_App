import 'package:extrahelper/core/format/when.dart';
import 'package:extrahelper/data/notifications/app_notification.dart';
import 'package:extrahelper/data/notifications/local_notifier.dart';
import 'package:extrahelper/features/notifications/notifications_providers.dart';
import 'package:extrahelper/features/notifications/notifications_screen.dart';
import 'package:extrahelper/features/tenant/tenant_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Order alerts: what a row means, who gets buzzed, what counts as unread,
/// and when the OS will still ask. All pure — the socket and the plugin are
/// the parts that need a real phone.

AppNotification _n(
  String id, {
  DateTime? at,
  String? actor,
  int? amount,
  String body = 'Table 4',
}) => AppNotification(
  id: id,
  tenantId: 't1',
  kind: NotificationKind.orderReady,
  title: 'Ready to serve',
  body: body,
  createdAt: at ?? DateTime.utc(2026, 9, 26, 12),
  actorId: actor,
  amountCents: amount,
);

void main() {
  group('row parsing', () {
    test('reads a full PostgREST / Realtime row', () {
      final n = AppNotification.fromJson({
        'id': 'n1',
        'tenant_id': 't1',
        'kind': 'bill_paid',
        'order_id': null,
        'bill_id': 'b1',
        'order_type': null,
        'table_label': '4',
        'amount_cents': 108000,
        'title': 'Bill paid',
        'body': 'Table 4',
        'actor_id': 'u1',
        'created_at': '2026-09-26T12:00:00+00:00',
      });
      expect(n.kind, NotificationKind.billPaid);
      expect(n.billId, 'b1');
      expect(n.amountCents, 108000);
      expect(n.actorId, 'u1');
      expect(n.createdAt, DateTime.utc(2026, 9, 26, 12));
      // No order on a bill event: the tap carries the bill instead.
      expect(n.payload, 'b1');
    });

    test('every server kind maps, and a new one does not throw', () {
      const wire = {
        'order_new': NotificationKind.orderNew,
        'order_preparing': NotificationKind.orderPreparing,
        'order_ready': NotificationKind.orderReady,
        'order_served': NotificationKind.orderServed,
        'order_billed': NotificationKind.orderBilled,
        'order_cancelled': NotificationKind.orderCancelled,
        'bill_paid': NotificationKind.billPaid,
      };
      wire.forEach((k, v) => expect(NotificationKind.fromWire(k), v));
      expect(
        NotificationKind.fromWire('order_teleported'),
        NotificationKind.unknown,
      );
    });

    test('a sparse payload still parses', () {
      final n = AppNotification.fromJson({'id': 'n2'});
      expect(n.kind, NotificationKind.unknown);
      expect(n.title, 'Order update');
      expect(n.amountCents, isNull);
      expect(n.payload, isNull);
    });

    test('the OS id is stable and non-negative', () {
      final a = _n('abc');
      expect(a.osId, _n('abc').osId);
      expect(a.osId, greaterThanOrEqualTo(0));
    });
  });

  group('detail line', () {
    test('adds the amount in the tenant currency', () {
      expect(_n('1', amount: 108000).detail('NPR'), 'Table 4 · NPR 1,080.00');
    });

    test('is just the body without an amount', () {
      expect(_n('1').detail('NPR'), 'Table 4');
    });
  });

  group('self-authored filtering', () {
    test('no buzz for what you did yourself', () {
      expect(shouldAlert(_n('1', actor: 'me'), currentUserId: 'me'), isFalse);
    });

    test('a colleague\'s change alerts', () {
      expect(shouldAlert(_n('1', actor: 'them'), currentUserId: 'me'), isTrue);
    });

    test('no actor (QR, webhook) always alerts', () {
      expect(shouldAlert(_n('1'), currentUserId: 'me'), isTrue);
    });
  });

  group('unread', () {
    final noon = DateTime.utc(2026, 9, 26, 12);
    final items = [
      _n('a', at: noon.add(const Duration(minutes: 2))),
      _n('b', at: noon),
      _n('c', at: noon.subtract(const Duration(minutes: 2))),
    ];

    final soon = noon.add(const Duration(hours: 1));

    test('no cursor: the last 24h is unread', () {
      expect(unreadCount(items, null, now: soon), 3);
    });

    test('no cursor: older than 24h is not', () {
      final later = noon.add(const Duration(hours: 25));
      expect(unreadCount(items, null, now: later), 0);
    });

    test('only rows strictly after the cursor', () {
      expect(unreadCount(items, noon, now: soon), 1);
      expect(isUnread(items[1], noon, now: soon), isFalse);
    });

    test('a stale cursor never reaches past 24h', () {
      final stale = noon.subtract(const Duration(days: 30));
      final later = noon.add(const Duration(hours: 24, minutes: 1));
      // Only 'a' (noon+2m) is inside the window ending at `later`.
      expect(unreadCount(items, stale, now: later), 1);
    });

    test('your own actions are never unread', () {
      final mine = _n(
        'm',
        actor: 'me',
        at: noon.add(const Duration(minutes: 5)),
      );
      expect(isUnread(mine, noon, userId: 'me', now: soon), isFalse);
      expect(isUnread(mine, noon, userId: 'them', now: soon), isTrue);
    });

    test('the feed reports the same count', () {
      expect(NotificationFeed.empty.unread, 0);
    });

    test('the later cursor wins', () {
      expect(laterCursor(noon, soon), soon);
      expect(laterCursor(soon, null), soon);
      expect(laterCursor(null, noon), noon);
    });
  });

  group('merging arrivals', () {
    final t0 = DateTime.utc(2026, 9, 26, 12);

    test('newest goes first', () {
      final merged = mergeIncoming([
        _n('old', at: t0),
      ], _n('new', at: t0.add(const Duration(seconds: 5))));
      expect(merged.map((n) => n.id), ['new', 'old']);
    });

    test('a replayed row is not added twice', () {
      final current = [_n('x', at: t0)];
      expect(
        identical(mergeIncoming(current, _n('x', at: t0)), current),
        isTrue,
      );
    });

    test('capped', () {
      final current = [
        for (var i = 0; i < 50; i++)
          _n('r$i', at: t0.subtract(Duration(minutes: i))),
      ];
      final merged = mergeIncoming(
        current,
        _n('fresh', at: t0.add(const Duration(minutes: 1))),
      );
      expect(merged, hasLength(50));
      expect(merged.first.id, 'fresh');
      expect(merged.any((n) => n.id == 'r49'), isFalse);
    });
  });

  group('OS permission', () {
    test('enabled is granted, whatever the history', () {
      expect(
        resolveAlertPermission(enabled: true, denials: 5, isIOS: true),
        AlertPermission.granted,
      );
    });

    test('iOS asks exactly once', () {
      expect(
        resolveAlertPermission(enabled: false, denials: 0, isIOS: true),
        AlertPermission.notAsked,
      );
      expect(
        resolveAlertPermission(enabled: false, denials: 1, isIOS: true),
        AlertPermission.blocked,
      );
    });

    test('Android shows the prompt twice before refusing for the user', () {
      expect(
        resolveAlertPermission(enabled: false, denials: 1, isIOS: false),
        AlertPermission.notAsked,
      );
      expect(
        resolveAlertPermission(enabled: false, denials: 2, isIOS: false),
        AlertPermission.blocked,
      );
    });
  });

  group('relative time', () {
    final now = DateTime(2026, 9, 26, 15, 0);

    test('recent', () {
      expect(
        relativeTime(now.subtract(const Duration(seconds: 20)), now: now),
        'just now',
      );
      expect(
        relativeTime(now.subtract(const Duration(minutes: 7)), now: now),
        '7 min ago',
      );
      expect(
        relativeTime(now.subtract(const Duration(hours: 2)), now: now),
        '2 h ago',
      );
    });

    test('earlier today is the clock, earlier days the date', () {
      expect(
        relativeTime(DateTime(2026, 9, 26, 8, 5), now: now),
        '8:05\u202fAM',
      );
      expect(
        relativeTime(DateTime(2026, 9, 24, 8, 5), now: now),
        'Sep 24, 2026',
      );
    });
  });

  group('bell', () {
    Widget app({required Set<String> permissions, int unread = 0}) =>
        ProviderScope(
          overrides: [
            permissionsProvider.overrideWith((ref) => permissions),
            unreadNotificationsProvider.overrideWithValue(unread),
          ],
          child: MaterialApp(
            home: Scaffold(appBar: AppBar(actions: const [NotificationBell()])),
          ),
        );

    testWidgets('absent without notifications.view', (tester) async {
      await tester.pumpWidget(app(permissions: {'kds.view'}));
      await tester.pump();
      expect(find.byType(IconButton), findsNothing);
    });

    testWidgets('shows the unread count, in words too', (tester) async {
      await tester.pumpWidget(
        app(permissions: {notificationsViewKey}, unread: 3),
      );
      await tester.pump();
      expect(find.text('3'), findsOneWidget);
      expect(find.byTooltip('Notifications, 3 unread'), findsOneWidget);
    });

    testWidgets('no badge when all read', (tester) async {
      await tester.pumpWidget(app(permissions: {notificationsViewKey}));
      await tester.pump();
      expect(find.byTooltip('Notifications'), findsOneWidget);
      expect(find.text('0'), findsNothing);
    });
  });
}
