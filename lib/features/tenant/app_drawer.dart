import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/theme/tokens.dart';
import 'tenant_providers.dart';
import 'tenant_switcher.dart';

/// Where you can go, and which restaurant you are in while you go there.
///
/// Destinations used to be icon buttons in the app bar, which put five taps in
/// the top-right corner — the hardest place to reach one-handed — and left the
/// restaurant name about 90px to render in. Here each one gets a full row with
/// its name spelled out, and the tenant gets the header.
class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Permissions decide what exists. The same keys the app bar used, with the
    // same reasoning — the server refuses these surfaces anyway, so this only
    // avoids offering a door that won't open.
    final canSeeKitchen = ref.watch(hasPermissionProvider('kds.view'));
    final canSeeReports = ref.watch(hasPermissionProvider('reports.view'));
    final canSeeStock = ref.watch(hasPermissionProvider('inventory.view'));
    // `audit_logs` RLS is owner/manager only; `order.void` is held by exactly
    // those two, so it is the honest key to hang the manager log on.
    final canReview = ref.watch(hasPermissionProvider('order.void'));
    final canSeeMenu = ref.watch(hasPermissionProvider('menu.view'));
    // Owner and manager by default. False while permissions load, which is the
    // right way round: a door that appears late is better than one that
    // vanishes under a thumb already moving towards it.
    // `staff.view` is Owner/Manager by default; `staff.edit` gates the
    // controls inside, so a viewer gets the roster without the levers.
    final canSeeTeam = ref.watch(hasPermissionProvider('staff.view'));
    final canSeeSettings = ref.watch(hasPermissionProvider('settings.view'));

    final location = GoRouterState.of(context).matchedLocation;

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const TenantDrawerHeader(),
            const Divider(height: 1),
            _DrawerItem(
              icon: Icons.point_of_sale_outlined,
              selectedIcon: Icons.point_of_sale,
              label: 'POS',
              route: Routes.home,
              location: location,
            ),
            if (canSeeKitchen)
              _DrawerItem(
                icon: Icons.soup_kitchen_outlined,
                selectedIcon: Icons.soup_kitchen,
                label: 'Kitchen',
                route: Routes.kds,
                location: location,
              ),
            if (canSeeReports)
              _DrawerItem(
                icon: Icons.insights_outlined,
                selectedIcon: Icons.insights,
                label: 'Dashboard',
                route: Routes.dashboard,
                location: location,
              ),
            // Same key as the dashboard: the day close exposes strictly less
            // than the web Sales tab a `reports.view` holder already sees.
            if (canSeeReports)
              _DrawerItem(
                icon: Icons.event_available_outlined,
                selectedIcon: Icons.event_available,
                label: 'Day close',
                route: Routes.dayClose,
                location: location,
              ),
            // `inventory.view` is Owner/Manager/Inventory, so a waiter never
            // sees the door; the RPCs enforce `inventory.edit` separately,
            // which is why a viewer still gets a read-only screen.
            if (canSeeStock)
              _DrawerItem(
                icon: Icons.inventory_2_outlined,
                selectedIcon: Icons.inventory_2,
                label: 'Store room',
                route: Routes.inventory,
                location: location,
              ),
            // `menu.view` is Owner/Manager only by default; `menu.edit` gates
            // the controls inside, so a custom role with view alone gets a
            // read-only screen rather than a door that refuses everything.
            if (canSeeMenu)
              _DrawerItem(
                icon: Icons.restaurant_menu_outlined,
                selectedIcon: Icons.restaurant_menu,
                label: 'Menu',
                route: Routes.menu,
                location: location,
              ),
            if (canReview)
              _DrawerItem(
                icon: Icons.fact_check_outlined,
                selectedIcon: Icons.fact_check,
                label: 'Manager log',
                route: Routes.managerLog,
                location: location,
              ),
            if (canSeeTeam)
              _DrawerItem(
                icon: Icons.groups_outlined,
                selectedIcon: Icons.groups,
                label: 'Team',
                route: Routes.team,
                location: location,
              ),
            const Divider(height: 1),
            if (canSeeSettings)
              _DrawerItem(
                icon: Icons.settings_outlined,
                selectedIcon: Icons.settings,
                label: 'Settings',
                route: Routes.settings,
                location: location,
              ),
            // No permission gate: whether this phone prints is a property of the
            // phone, not of the person holding it, and the screen itself is
            // read-only against the registry.
            _DrawerItem(
              icon: Icons.print_outlined,
              selectedIcon: Icons.print,
              label: 'Printing',
              route: Routes.printing,
              location: location,
            ),
            _DrawerItem(
              icon: Icons.person_outline,
              selectedIcon: Icons.person,
              label: 'Account',
              route: Routes.account,
              location: location,
            ),
            if (kDebugMode)
              _DrawerItem(
                icon: Icons.palette_outlined,
                selectedIcon: Icons.palette,
                label: 'Design system',
                route: Routes.designGallery,
                location: location,
              ),
          ],
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.route,
    required this.location,
  });

  final IconData icon;

  /// The filled variant. Selection is not carried by the tint alone — a filled
  /// glyph and a heavier label say it in greyscale too.
  final IconData selectedIcon;

  final String label;
  final String route;
  final String location;

  @override
  Widget build(BuildContext context) {
    // Prefix match so a pushed leaf still highlights the destination it came
    // from — standing on `/settings/general` is still standing in Settings.
    // `/` is excluded explicitly: it prefixes everything.
    final selected =
        location == route ||
        (route != Routes.home && location.startsWith('$route/'));
    final theme = Theme.of(context);
    return ListTile(
      minTileHeight: Tokens.tapTarget + 8,
      selected: selected,
      leading: Icon(selected ? selectedIcon : icon),
      title: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyLarge?.copyWith(
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      onTap: () => _go(context, route, selected: selected),
    );
  }

  /// Close the drawer, then land on the destination with nothing stacked
  /// underneath it. Destinations replace each other; only leaves (composer,
  /// stock count) push, so Back always means "return to the POS".
  static void _go(
    BuildContext context,
    String route, {
    required bool selected,
  }) {
    final router = GoRouter.of(context);
    Scaffold.of(context).closeDrawer();
    if (selected) return;
    while (router.canPop()) {
      router.pop();
    }
    router.go(route);
  }
}
