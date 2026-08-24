import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_scaffold.dart';
import '../../core/widgets/notice.dart';
import '../../data/sync/sync_providers.dart';
import '../pos/pos_screen.dart';
import 'tenant_providers.dart';

/// The signed-in shell: the POS is the app's home surface, because taking an
/// order is what a waiter opened this for.
///
/// Everything else — dashboard, store room, manager log, account — is a drawer
/// destination. They used to be icon buttons crowded into the app bar, which
/// cost the restaurant name its room and put five taps in the corner hardest to
/// reach one-handed.
///
/// The POS tabs live in the app bar's `bottom` rather than in the body, so the
/// bar and the tabs read as one band instead of two stacked ones.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell>
    with SingleTickerProviderStateMixin {
  /// Four, always. The Bills and Completed tabs render a "no access" body
  /// rather than being removed for a cashier-less role: permissions resolve
  /// *after* the first build, and a `TabController` whose length changes under
  /// it throws. A fixed four is fine; a length that moves with permissions is
  /// not.
  ///
  /// Built in [initState], **not** as a lazy `late final` initialiser. Anyone
  /// who never sees the tab bar — a kitchen role, or any launch where identity
  /// has not resolved — never reads this field, which made `dispose()` the
  /// first read: the controller was then constructed while the element was
  /// already deactivated, and `createTicker` looks up a `TickerMode` ancestor
  /// that is no longer there. It asserts in debug and builds a controller only
  /// to throw it away in release.
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canSeeTables = ref.watch(hasPermissionProvider('tables.view'));
    final canOrder = ref.watch(hasPermissionProvider('order.create'));
    // What the shell actually knows. This used to be inferred locally — "tenant
    // resolved AND permissions non-null" — because `permissionsProvider`
    // answered `{}` for an unresolved tenant and the shell had to defend
    // itself. The provider no longer lies, so the guess is gone.
    final status = ref.watch(identityStatusProvider);

    // Permissions decide what exists, and default to false while loading, so a
    // surface never flashes up and then vanishes.
    final showPos =
        status == IdentityStatus.ready && (canSeeTables || canOrder);

    return AppScaffold(
      title: 'POS',
      // No tabs over a spinner or over a locked-out message — they would
      // promise two surfaces that aren't there.
      bottom: showPos
          ? TabBar(
              controller: _tabs,
              // Four labels on a phone bar: "Done" rather than "Completed", so
              // the row still fits at a raised text size instead of clipping or
              // turning into something you have to scroll to discover.
              tabs: const [
                Tab(text: 'Tables'),
                Tab(text: 'Orders'),
                Tab(text: 'Bills'),
                Tab(text: 'Done'),
              ],
            )
          : null,
      body: switch (status) {
        // "No ordering access" is a verdict, and a verdict needs an answer to
        // be based on. It is reachable from `ready` and nowhere else.
        IdentityStatus.ready =>
          showPos ? PosScreen(tabs: _tabs) : const _NoPosAccess(),
        IdentityStatus.unavailable => const _IdentityUnavailable(),
        // `noRestaurant` is the router's to act on; while it does, this reads
        // the same as any other not-yet.
        IdentityStatus.unknown ||
        IdentityStatus.noRestaurant => const _CheckingAccess(),
      },
    );
  }
}

/// Identity has not answered yet.
///
/// A bare spinner was what this used to be, and on a poor connection it could
/// sit there indefinitely with no word of what it was waiting for and no way to
/// prod it. Name the wait, and offer the nudge.
class _CheckingAccess extends ConsumerWidget {
  const _CheckingAccess();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Checking what you can do here',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => _retryIdentity(ref),
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Identity could not be read and there is nothing cached to stand in.
///
/// Two different sentences, because they need two different things from the
/// person reading them: offline is not an error and has a plain remedy, while
/// a failure with coverage is worth showing the detail of.
class _IdentityUnavailable extends ConsumerWidget {
  const _IdentityUnavailable();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(isOnlineProvider).valueOrNull ?? true;
    final error = ref.watch(identityErrorProvider);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: online
            ? RetryNotice(
                message: "Couldn't load your access for this restaurant.",
                detail: '$error',
                onRetry: () => _retryIdentity(ref),
              )
            : RetryNotice(
                message:
                    "You're offline, and this phone hasn't saved your access "
                    'for this restaurant yet. Connect once and it will be here '
                    'next time.',
                icon: Icons.cloud_off,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                onRetry: () => _retryIdentity(ref),
              ),
      ),
    );
  }
}

/// Both reads, together: permissions are derived from the tenant, so refreshing
/// one without the other only ever half-recovers.
void _retryIdentity(WidgetRef ref) {
  ref
    ..invalidate(membershipsProvider)
    ..invalidate(permissionsProvider);
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
              'owner or manager can change that under Team.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
