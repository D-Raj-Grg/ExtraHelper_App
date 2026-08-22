import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/supabase/supabase_providers.dart';
import '../features/auth/join_code_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/dev/design_gallery.dart';
import '../features/inventory/inventory_screen.dart';
import '../features/kds/kds_screen.dart';
import '../features/menu/menu_screen.dart';
import '../features/pos/bill_view_screen.dart';
import '../features/pos/checkout_screen.dart';
import '../features/pos/manager_ops.dart';
import '../features/settings/printing_screen.dart';
import '../features/tenant/account_screen.dart';
import '../features/tenant/home_shell.dart';
import '../features/tenant/tenant_providers.dart';
import 'redirect.dart';

/// Routes. Kept as constants so a typo is a compile error, not a 404.
abstract final class Routes {
  static const home = '/';
  static const login = '/login';
  static const join = '/join';
  static const kds = '/kitchen';
  static const dashboard = '/dashboard';
  static const inventory = '/store-room';
  static const menu = '/menu';
  static const managerLog = '/manager-log';
  static const printing = '/printing';
  static const account = '/account';
  static const designGallery = '/dev/design';

  /// Checkout. Pushed on top of the POS rather than replacing it — a cashier
  /// backs out of a bill onto the board they came from.
  static const bill = '/bill/:billId';

  static String billPath(String billId) => '/bill/$billId';

  /// The bill as a document rather than a set of levers. Pushed on top of
  /// checkout — someone looks at the slip, then backs out to the controls.
  static const billView = '/bill/:billId/view';

  static String billViewPath(String billId) => '/bill/$billId/view';
}

/// The router, with **one** place that decides where a user belongs.
///
/// Screens never navigate on sign-in or sign-out; they change auth state and
/// this redirect resolves it. Two sources of that decision would eventually
/// disagree, and the failure mode is a user stuck on a screen they can't use.
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);

  // Re-evaluate the redirect whenever auth or membership state moves: a session
  // that expires while backgrounded, an approval that lands, a tenant switch.
  // Permissions too: they decide whether the POS is even a place this person
  // can stand, and they arrive after the memberships do.
  ref
    ..listen(authStateProvider, (_, _) => refresh.value++)
    ..listen(membershipsProvider, (_, _) => refresh.value++)
    ..listen(permissionsProvider, (_, _) => refresh.value++)
    ..onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: Routes.home,
    refreshListenable: refresh,
    redirect: (context, state) => resolveRedirect(
      signedIn: ref.read(currentUserProvider) != null,
      memberships: ref.read(membershipsProvider),
      permissions: ref.read(permissionsProvider).valueOrNull,
      location: state.matchedLocation,
    ),
    routes: [
      GoRoute(
        path: Routes.home,
        builder: (context, state) => const HomeShell(),
      ),
      GoRoute(
        path: Routes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: Routes.join,
        builder: (context, state) => const JoinCodeScreen(),
      ),
      // Drawer destinations. Real routes rather than imperative pushes, so the
      // drawer can say which one you are on without tracking it itself.
      GoRoute(path: Routes.kds, builder: (context, state) => const KdsScreen()),
      GoRoute(
        path: Routes.dashboard,
        builder: (context, state) => const DashboardScreen(),
      ),
      GoRoute(
        path: Routes.inventory,
        builder: (context, state) => const InventoryScreen(),
      ),
      GoRoute(
        path: Routes.menu,
        builder: (context, state) => const MenuScreen(),
      ),
      GoRoute(
        path: Routes.managerLog,
        builder: (context, state) => const ManagerLogScreen(),
      ),
      GoRoute(
        path: Routes.printing,
        builder: (context, state) => const PrintingScreen(),
      ),
      GoRoute(
        path: Routes.account,
        builder: (context, state) => const AccountScreen(),
      ),
      // No permission branch in the redirect for this one. Someone without
      // `checkout.view` is never shown a way in, and every RPC behind the
      // screen refuses them anyway — whereas a redirect that reads permissions
      // fires before they have loaded and bounces the cashier off their own
      // bill (see the note on the listener above).
      GoRoute(
        path: Routes.bill,
        builder: (context, state) =>
            CheckoutScreen(billId: state.pathParameters['billId']!),
      ),
      // Same reasoning on permissions, and read-only besides.
      GoRoute(
        path: Routes.billView,
        builder: (context, state) =>
            BillViewScreen(billId: state.pathParameters['billId']!),
      ),
      // Debug-only: the greyscale check for "never colour alone" needs every
      // state on one screen, which real screens can't offer.
      if (kDebugMode)
        GoRoute(
          path: Routes.designGallery,
          builder: (context, state) => const DesignGallery(),
        ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.help_outline, size: 40),
              const SizedBox(height: 12),
              Text(
                "That screen doesn't exist.",
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => context.go(Routes.home),
                child: const Text('Go back'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
});
