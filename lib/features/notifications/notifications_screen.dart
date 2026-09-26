import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_scaffold.dart';
import '../../app/router.dart';
import '../../core/format/when.dart';
import '../../core/theme/tokens.dart';
import '../../data/notifications/app_notification.dart';
import '../../data/notifications/local_notifier.dart';
import '../tenant/tenant_providers.dart';
import 'notifications_providers.dart';

/// The bell in the app bar. Draws nothing without `notifications.view`, so a
/// cook's app bar is not carrying a door that opens onto an empty room.
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(canSeeNotificationsProvider)) return const SizedBox.shrink();
    final unread = ref.watch(unreadNotificationsProvider);
    // The count is the meaning; the badge colour only reinforces it.
    final label = unread == 0
        ? 'Notifications'
        : 'Notifications, $unread unread';
    return IconButton(
      tooltip: label,
      constraints: const BoxConstraints(
        minWidth: Tokens.tapTarget,
        minHeight: Tokens.tapTarget,
      ),
      onPressed: () => context.push(Routes.notifications),
      icon: Semantics(
        label: label,
        excludeSemantics: true,
        child: Badge.count(
          count: unread,
          isLabelVisible: unread > 0,
          child: Icon(
            unread > 0 ? Icons.notifications_active : Icons.notifications_none,
          ),
        ),
      ),
    );
  }
}

/// Every step of every order, newest first: the phone's copy of the web bell.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canSee = ref.watch(canSeeNotificationsProvider);
    final feed = ref.watch(notificationFeedProvider);
    final unread = feed.valueOrNull?.unread ?? 0;

    return AppScaffold(
      title: 'Notifications',
      showDrawer: false,
      showBell: false,
      actions: [
        if (canSee && unread > 0)
          TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(Tokens.tapTarget, Tokens.tapTarget),
            ),
            onPressed: () => _markAllRead(context, ref),
            child: const Text('Mark all read'),
          ),
      ],
      body: !canSee
          ? const _Message(
              icon: Icons.notifications_off_outlined,
              title: "Your role doesn't include order alerts.",
              detail:
                  'Ask the owner to add "View notifications" to your role '
                  'on the Team screen.',
            )
          : Column(
              children: [
                const _AlertsOffBanner(),
                Expanded(
                  child: feed.when(
                    // A rebuild or a failed refetch keeps the list on screen.
                    skipLoadingOnReload: true,
                    skipError: feed.hasValue,
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => _Message(
                      icon: Icons.cloud_off_outlined,
                      title: "Couldn't load notifications.",
                      detail: 'Check the connection, then try again.',
                      action: FilledButton.tonal(
                        onPressed: () =>
                            ref.invalidate(notificationFeedProvider),
                        child: const Text('Try again'),
                      ),
                    ),
                    data: (f) => RefreshIndicator(
                      onRefresh: () =>
                          ref.read(notificationFeedProvider.notifier).refresh(),
                      child: f.items.isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: const [
                                SizedBox(height: 80),
                                _Message(
                                  icon: Icons.notifications_none,
                                  title: 'Nothing yet today.',
                                  detail:
                                      'New orders, dishes ready to serve and '
                                      'payments show up here the moment they '
                                      'happen.',
                                ),
                              ],
                            )
                          : ListView.separated(
                              physics: const AlwaysScrollableScrollPhysics(),
                              itemCount: f.items.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, i) {
                                final n = f.items[i];
                                return _NotificationRow(
                                  key: ValueKey(n.id),
                                  notification: n,
                                  unread: f.isUnreadRow(n),
                                );
                              },
                            ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _markAllRead(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(notificationFeedProvider.notifier).markAllRead();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text("Couldn't mark them read: $e")),
      );
    }
  }
}

class _NotificationRow extends ConsumerWidget {
  const _NotificationRow({
    super.key,
    required this.notification,
    required this.unread,
  });

  final AppNotification notification;
  final bool unread;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final n = notification;
    final currency = ref.watch(activeTenantProvider)?.currency ?? '';
    final (icon, tint) = _look(context, n.kind);

    // There is no order-detail screen on the phone yet. A bill is the one
    // thing a row can open, and only for someone who may look at bills.
    final billId = n.billId;
    final canOpenBill =
        billId != null && ref.watch(hasPermissionProvider('checkout.view'));

    return ListTile(
      minTileHeight: Tokens.tapTarget + 16,
      leading: Icon(icon, color: tint),
      title: Row(
        children: [
          Expanded(
            child: Text(
              n.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: unread ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
          // Weight carries "unread"; the dot and the word in the semantics
          // label back it up, so it survives greyscale and a screen reader.
          if (unread)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Semantics(
                label: 'unread',
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
        ],
      ),
      subtitle: Text(
        n.detail(currency),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        relativeTime(n.createdAt),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      onTap: canOpenBill
          ? () => context.push(Routes.billViewPath(billId))
          : null,
    );
  }

  /// A distinct glyph per step, so the list reads without colour. Colour
  /// follows the app-wide semantic map: good for done, info for moving,
  /// attention for money owed, danger for cancelled.
  static (IconData, Color?) _look(BuildContext context, NotificationKind kind) {
    final s = context.semantic;
    return switch (kind) {
      NotificationKind.orderNew => (Icons.receipt_long_outlined, s.info),
      NotificationKind.orderPreparing => (Icons.soup_kitchen_outlined, s.info),
      NotificationKind.orderReady => (Icons.room_service_outlined, s.warning),
      NotificationKind.orderServed => (Icons.check_circle_outline, s.good),
      NotificationKind.orderBilled => (
        Icons.request_quote_outlined,
        s.attention,
      ),
      NotificationKind.orderCancelled => (Icons.cancel_outlined, s.danger),
      NotificationKind.billPaid => (Icons.payments_outlined, s.good),
      NotificationKind.unknown => (Icons.notifications_none, null),
    };
  }
}

/// Says so when this phone will not actually buzz — the permission is off or
/// the device is muted — and offers the one tap that fixes it.
class _AlertsOffBanner extends ConsumerWidget {
  const _AlertsOffBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permission = ref.watch(alertPermissionProvider).valueOrNull;
    final muted = ref.watch(alertsMutedProvider);
    if (permission == null) return const SizedBox.shrink();
    if (permission == AlertPermission.granted && !muted) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: ListTile(
        minTileHeight: Tokens.tapTarget + 8,
        leading: const Icon(Icons.notifications_paused_outlined),
        title: Text(
          muted
              ? 'Alerts are muted on this phone.'
              : 'Alerts are off on this phone.',
        ),
        subtitle: const Text('The list still updates. Tap to change.'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push(Routes.settingsNotifications),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.detail,
    this.action,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 12), action!],
          ],
        ),
      ),
    );
  }
}
