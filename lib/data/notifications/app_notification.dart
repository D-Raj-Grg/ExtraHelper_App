import '../../core/format/money.dart';

/// What happened to an order — one value per `notifications.kind`.
///
/// The server writes these from triggers on `orders.status` and `bills.status`
/// (`supabase/migrations/20260926120000_order_notifications.sql` in the web
/// repo). A kind the phone does not know yet parses to [unknown] rather than
/// throwing: a newer web release must never crash an older phone's feed.
enum NotificationKind {
  orderNew,
  orderPreparing,
  orderReady,
  orderServed,
  orderBilled,
  orderCancelled,
  billPaid,
  unknown;

  static NotificationKind fromWire(String? wire) => switch (wire) {
    'order_new' => orderNew,
    'order_preparing' => orderPreparing,
    'order_ready' => orderReady,
    'order_served' => orderServed,
    'order_billed' => orderBilled,
    'order_cancelled' => orderCancelled,
    'bill_paid' => billPaid,
    _ => unknown,
  };
}

/// One row of `public.notifications`.
///
/// [title] and [body] are written server-side ("Ready to serve" / "Table 4"),
/// so the phone and the web bell say exactly the same words.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.tenantId,
    required this.kind,
    required this.title,
    required this.body,
    required this.createdAt,
    this.orderId,
    this.billId,
    this.orderType,
    this.tableLabel,
    this.amountCents,
    this.actorId,
  });

  final String id;
  final String tenantId;
  final NotificationKind kind;
  final String title;
  final String body;
  final DateTime createdAt;
  final String? orderId;
  final String? billId;
  final String? orderType;
  final String? tableLabel;
  final int? amountCents;

  /// Who caused it. Null for service-role and QR paths — nobody tapped
  /// anything, so everybody should hear about it.
  final String? actorId;

  /// Parses a PostgREST row or a Realtime `newRecord` — the two have the same
  /// shape. Tolerant of missing fields, because a Realtime payload for a column
  /// added later must not throw inside a socket callback.
  static AppNotification fromJson(Map<String, dynamic> j) => AppNotification(
    id: (j['id'] as String?) ?? '',
    tenantId: (j['tenant_id'] as String?) ?? '',
    kind: NotificationKind.fromWire(j['kind'] as String?),
    title: (j['title'] as String?) ?? 'Order update',
    body: (j['body'] as String?) ?? '',
    createdAt:
        DateTime.tryParse((j['created_at'] as String?) ?? '') ??
        DateTime.now().toUtc(),
    orderId: j['order_id'] as String?,
    billId: j['bill_id'] as String?,
    orderType: j['order_type'] as String?,
    tableLabel: j['table_label'] as String?,
    amountCents: (j['amount_cents'] as num?)?.toInt(),
    actorId: j['actor_id'] as String?,
  );

  /// The line under the title: where, plus how much when there is a sum.
  /// "Table 4 · NPR 1,080.00". Formatted through [money] with the tenant's
  /// currency — never a hand-rolled `toStringAsFixed`.
  String detail(String currency) {
    final cents = amountCents;
    if (cents == null) return body;
    final sum = money(cents, currency);
    return body.isEmpty ? sum : '$body · $sum';
  }

  /// What the tap on an OS notification carries back. The order when there is
  /// one, else the bill.
  String? get payload => orderId ?? billId;

  /// A stable 31-bit id for the OS, so the same event arriving twice replaces
  /// its banner instead of stacking a duplicate.
  int get osId => id.hashCode & 0x7fffffff;
}

/// Whether this device should raise an OS alert for [n].
///
/// The person who tapped "Ready" does not need their own phone buzzing to tell
/// them so. Rows with no actor (QR orders, webhooks) always alert.
bool shouldAlert(AppNotification n, {required String? currentUserId}) {
  final actor = n.actorId;
  if (actor == null || currentUserId == null) return true;
  return actor != currentUserId;
}

/// How far back "unread" ever reaches. Same window as the web bell
/// (`UNREAD_FALLBACK_MS` in `lib/notification-constants.ts`), so a user who has
/// never marked anything read sees the same badge on both.
const unreadWindow = Duration(hours: 24);

/// Unread means newer than the per-user cursor in `notification_reads` — but
/// never older than [unreadWindow], and never something you did yourself.
/// Mirrors the web's `isUnread` so the phone and browser badges agree.
bool isUnread(
  AppNotification n,
  DateTime? lastReadAt, {
  String? userId,
  DateTime? now,
}) {
  if (userId != null && n.actorId == userId) return false;
  final floor = (now ?? DateTime.now()).subtract(unreadWindow);
  final since = lastReadAt != null && lastReadAt.isAfter(floor)
      ? lastReadAt
      : floor;
  return n.createdAt.isAfter(since);
}

int unreadCount(
  Iterable<AppNotification> items,
  DateTime? lastReadAt, {
  String? userId,
  DateTime? now,
}) => items
    .where((n) => isUnread(n, lastReadAt, userId: userId, now: now))
    .length;

/// Puts a realtime arrival at the head of the feed, once. Realtime can deliver
/// a row the initial fetch already returned, and a reconnect can replay one.
List<AppNotification> mergeIncoming(
  List<AppNotification> current,
  AppNotification incoming, {
  int cap = 50,
}) {
  if (current.any((n) => n.id == incoming.id)) return current;
  final next = [incoming, ...current]
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return next.length > cap ? next.sublist(0, cap) : next;
}
