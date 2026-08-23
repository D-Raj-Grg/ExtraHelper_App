import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_scaffold.dart';
import '../../app/router.dart';
import '../../core/format/money.dart';
import '../../core/theme/theme_mode_provider.dart';
import '../../core/theme/tokens.dart';
import '../../data/supabase/auth_repository.dart';
import '../../data/supabase/supabase_providers.dart';
import 'tenant_providers.dart';

/// Who you are, where you are, and what you're allowed to do.
///
/// Useful for checking why a button is missing — not something to look at
/// mid-service, which is why it is a drawer destination rather than chrome.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  /// Confirm, then delete.
  ///
  /// The server refuses while the caller is the only owner of a restaurant, or
  /// while their account is attached to cash records that have to be kept. Both
  /// messages tell the user what to do instead, so they are shown as written
  /// rather than flattened into "couldn't delete account".
  static Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete your account?'),
        content: const Text(
          'This removes your ExtraHelper login and your membership of every '
          'restaurant you are in. Orders, bills and cash records you took stay '
          'with the restaurant. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep my account'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete account'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(authRepositoryProvider).deleteAccount();
      // Deleting signs the user out, and the router takes them to login.
    } on AuthFailure catch (e) {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Can't delete yet"),
          content: Text(e.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tenant = ref.watch(activeTenantProvider);
    final permissions = ref.watch(permissionsProvider);
    final user = ref.watch(currentUserProvider);
    final themeMode = ref.watch(themeModeProvider);

    return AppScaffold(
      title: 'Account',
      actions: [
        IconButton(
          tooltip: 'Sign out',
          icon: const Icon(Icons.logout),
          onPressed: () => ref.read(authRepositoryProvider).signOut(),
        ),
      ],
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(membershipsProvider);
          ref.invalidate(permissionsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (tenant != null) ...[
              _Row(label: 'Signed in', value: user?.email ?? '—'),
              _Row(label: 'Restaurant', value: tenant.name),
              _Row(
                label: 'Currency',
                value:
                    '${tenant.currency}  ·  ${money(123456, tenant.currency)}',
              ),
              _Row(label: 'Timezone', value: tenant.timezone),
              // Named here because this is the screen people look at when they
              // want to know what the restaurant is configured as. Changing it
              // is Settings' job — this screen is a mirror, not a control
              // panel.
              _Row(label: 'Day starts at', value: 'Set in Settings → General'),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.settings_outlined),
                title: const Text('Restaurant settings'),
                subtitle: const Text(
                  'Currency, timezone, charges, receipt and printers.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(Routes.settings),
              ),
              const SizedBox(height: 8),
            ],
            // Appearance moved to Settings → Appearance, where it sits beside
            // the other per-device choices instead of in the middle of a page
            // about who you are signed in as.
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.palette_outlined),
              title: const Text('Appearance'),
              subtitle: Text('${themeModeLabel(themeMode)} · set per device'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(Routes.settingsAppearance),
            ),
            const SizedBox(height: 24),

            Text('What you can do here', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'From get_my_permissions — the server decides, never a role string '
              'held in the app.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            permissions.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => _ErrorState(
                message: "Couldn't load your permissions.",
                detail: '$e',
                onRetry: () => ref.invalidate(permissionsProvider),
              ),
              data: (keys) => keys.isEmpty
                  ? Text(
                      'No permissions returned for this restaurant. Ask an owner '
                      'to check your role.',
                      style: theme.textTheme.bodyMedium,
                    )
                  : Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final key in _surfaces.entries)
                          if (keys.contains(key.key))
                            Chip(
                              avatar: const Icon(Icons.check, size: 16),
                              label: Text(key.value),
                            ),
                      ],
                    ),
            ),

            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 12),
            Text('Delete account', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Removes your login and your membership of every restaurant. '
              'What you recorded stays with the restaurant.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                  side: BorderSide(color: theme.colorScheme.error),
                  minimumSize: const Size(0, 44),
                ),
                icon: const Icon(Icons.delete_forever_outlined),
                label: const Text('Delete my account'),
                onPressed: () => _confirmDelete(context, ref),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

/// Permission key → the surface it unlocks. Only keys this app will actually
/// use — the full catalog is 35 keys and most are web-only surfaces.
const _surfaces = {
  'order.create': 'Take orders',
  'order.fire': 'Fire to kitchen',
  'order.void': 'Void lines',
  'tables.view': 'See tables',
  'tables.edit': 'Change table state',
  'menu.view': 'See menu',
  'kds.view': 'Kitchen display',
  'payment.take': 'Take payment',
  'reports.view': 'Reports',
};

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: theme.textTheme.labelMedium),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    required this.detail,
    required this.onRetry,
  });

  final String message;
  final String detail;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.error.withValues(alpha: 0.1),
        border: Border.all(color: scheme.error, width: 1.5),
        borderRadius: BorderRadius.circular(Tokens.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline, size: 20, color: scheme.error),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: scheme.error),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(detail, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}
