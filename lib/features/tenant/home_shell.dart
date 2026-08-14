import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_scaffold.dart';
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
  late final TabController _tabs = TabController(length: 4, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canSeeTables = ref.watch(hasPermissionProvider('tables.view'));
    final canOrder = ref.watch(hasPermissionProvider('order.create'));
    // A tenant that hasn't resolved yet makes `permissionsProvider` answer with
    // an empty set — which reads as "loaded, and you may do nothing", so the
    // shell flashed "No ordering access" at every launch before settling. Wait
    // for the tenant too: a surface must never appear and then vanish.
    final permissionsLoaded =
        ref.watch(activeTenantProvider) != null &&
        ref.watch(permissionsProvider).valueOrNull != null;

    // Permissions decide what exists, and default to false while loading, so a
    // surface never flashes up and then vanishes.
    final showPos = permissionsLoaded && (canSeeTables || canOrder);

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
      body: !permissionsLoaded
          ? const Center(child: CircularProgressIndicator())
          : showPos
          ? PosScreen(tabs: _tabs)
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
