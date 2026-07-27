import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format/money.dart';
import '../../core/theme/tokens.dart';
import '../../data/supabase/auth_repository.dart';
import '../../data/supabase/supabase_providers.dart';
import '../pos/pos_screen.dart';
import 'tenant_providers.dart';
import 'tenant_switcher.dart';

/// The signed-in shell: the POS is the app's home surface, because taking an
/// order is what a waiter opened this for.
///
/// The account/permissions view moved behind the person icon — useful for
/// checking why a button is missing, not something to look at mid-service.
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canSeeTables = ref.watch(hasPermissionProvider('tables.view'));
    final canOrder = ref.watch(hasPermissionProvider('order.create'));
    final permissionsLoaded =
        ref.watch(permissionsProvider).valueOrNull != null;

    return Scaffold(
      appBar: AppBar(
        title: const TenantSwitcher(),
        actions: [
          IconButton(
            tooltip: 'Account',
            icon: const Icon(Icons.person_outline),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const AccountScreen()),
            ),
          ),
          if (kDebugMode)
            IconButton(
              tooltip: 'Design system',
              icon: const Icon(Icons.palette_outlined),
              onPressed: () => context.push('/dev/design'),
            ),
        ],
      ),
      // Permissions decide what exists, and default to false while loading, so
      // a surface never flashes up and then vanishes.
      body: !permissionsLoaded
          ? const Center(child: CircularProgressIndicator())
          : (canSeeTables || canOrder)
          ? const PosScreen()
          : const _NoPosAccess(),
    );
  }
}

/// Signed in, in a restaurant, but without the keys to take orders — a real
/// state for a kitchen or inventory role. Say which, and what to do about it.
class _NoPosAccess extends StatelessWidget {
  const _NoPosAccess();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lock_outline,
              size: 40,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text('No ordering access', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              "Your role in this restaurant doesn't include taking orders. An "
              'owner or manager can change that on the web app under Team.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Who you are, where you are, and what you're allowed to do.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tenant = ref.watch(activeTenantProvider);
    final permissions = ref.watch(permissionsProvider);
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Account'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authRepositoryProvider).signOut(),
          ),
        ],
      ),
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
              const SizedBox(height: 20),
            ],
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
