import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_scaffold.dart';
import '../../core/theme/tokens.dart';
import '../../data/notifications/local_notifier.dart';
import '../notifications/notifications_providers.dart';

/// Whether this phone buzzes for order updates, and the way back when it
/// doesn't.
///
/// Two separate switches, deliberately. The OS permission is the phone's; this
/// app can ask once and then only point at Settings. Mute is the app's, per
/// device: the counter tablet can stay quiet while the waiter's phone rings.
class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final canSee = ref.watch(canSeeNotificationsProvider);
    final permission = ref.watch(alertPermissionProvider);
    final muted = ref.watch(alertsMutedProvider);

    return AppScaffold(
      title: 'Notifications',
      showDrawer: false,
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (!canSee)
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text("Your role doesn't include order alerts."),
              subtitle: Text(
                'Ask the owner to add "View notifications" to your role. '
                'Until then this phone has nothing to alert about.',
              ),
            ),
          permission.when(
            loading: () => const ListTile(
              leading: Icon(Icons.hourglass_empty),
              title: Text('Checking this phone…'),
            ),
            error: (_, _) => const ListTile(
              leading: Icon(Icons.help_outline),
              title: Text("Couldn't check this phone's notification setting."),
            ),
            data: (p) => _PermissionTile(permission: p),
          ),
          const Divider(),
          SwitchListTile(
            secondary: Icon(
              muted
                  ? Icons.notifications_off_outlined
                  : Icons.notifications_active_outlined,
            ),
            title: const Text('Mute alerts on this phone'),
            subtitle: Text(
              muted
                  ? 'Muted — no banner or sound. The bell still counts them.'
                  : 'Banner and sound for every order update.',
            ),
            value: muted,
            onChanged: (v) => ref.read(alertsMutedProvider.notifier).set(v),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              'Alerts arrive while ExtraHelper is open or in the background. '
              "If the app is closed completely, they can't reach this phone "
              'yet — keep it open during service. You never get an alert for '
              'something you did yourself.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionTile extends ConsumerWidget {
  const _PermissionTile({required this.permission});

  final AlertPermission permission;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.semantic;
    final (icon, tint, title, detail, button) = switch (permission) {
      AlertPermission.granted => (
        Icons.check_circle_outline,
        s.good,
        'On',
        'This phone is allowed to show order alerts.',
        null,
      ),
      AlertPermission.notAsked => (
        Icons.notifications_none,
        s.warning,
        'Off',
        'Turn on to get a banner and sound when orders are new, ready, '
            'served or paid.',
        'Turn on',
      ),
      AlertPermission.blocked => (
        Icons.block,
        s.danger,
        'Blocked in phone settings',
        "The phone won't ask again. Open its settings, find Notifications, "
            'and allow ExtraHelper.',
        'Open phone settings',
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          minTileHeight: Tokens.tapTarget + 12,
          leading: Icon(icon, color: tint),
          title: Text('Phone permission: $title'),
          subtitle: Text(detail),
        ),
        if (button != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(Tokens.tapTarget),
              ),
              onPressed: () => ref.read(alertSetupProvider).enable(),
              child: Text(button),
            ),
          ),
      ],
    );
  }
}
