import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/supabase/supabase_providers.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/onboarding_screen.dart';
import '../features/auth/signup_screen.dart';
import '../features/auth/verify_email_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/dev/design_gallery.dart';
import '../features/inventory/inventory_screen.dart';
import '../features/kds/kds_screen.dart';
import '../features/menu/menu_screen.dart';
import '../features/pos/bill_view_screen.dart';
import '../features/pos/checkout_screen.dart';
import '../features/pos/manager_ops.dart';
import '../features/reports/day_close_screen.dart';
import '../features/settings/appearance_screen.dart';
import '../features/settings/branches_screen.dart';
import '../features/settings/charges_settings_screen.dart';
import '../features/settings/danger_reset_screen.dart';
import '../features/settings/danger_screen.dart';
import '../features/settings/general_settings_screen.dart';
import '../features/settings/plan_usage_screen.dart';
import '../features/settings/printers_screen.dart';
import '../features/settings/printing_screen.dart';
import '../features/settings/profile_screen.dart';
import '../features/settings/receipt_settings_screen.dart';
import '../features/settings/settings_hub_screen.dart';
import '../features/team/team_screen.dart';
import '../features/tenant/account_screen.dart';
import '../features/tenant/home_shell.dart';
import '../features/tenant/tenant_providers.dart';
import '../features/welcome/welcome_providers.dart';
import '../features/welcome/welcome_screen.dart';
import 'redirect.dart';

/// Routes. Kept as constants so a typo is a compile error, not a 404.
abstract final class Routes {
  static const home = '/';

  /// The first-launch pitch. A real route rather than a modal over login, so
  /// the one place that decides where a user belongs keeps deciding it.
  static const welcome = '/welcome';
  static const login = '/login';
  static const signup = '/signup';

  /// Email confirmation. Carries `?email=` because there is no session yet to
  /// read the address back from.
  static const verify = '/verify';

  /// Where a signed-in user with no restaurant lands. Still `/join` — the
  /// screen grew a "create a restaurant" branch, but nothing is served by
  /// renaming a path that other code and muscle memory already know.
  static const join = '/join';
  static const kds = '/kitchen';
  static const dashboard = '/dashboard';
  static const dayClose = '/day-close';
  static const inventory = '/store-room';
  static const menu = '/menu';

  /// Staff and roles. A destination rather than a settings leaf: on the web it
  /// is its own top-level page, and on a phone the job — approve the person
  /// standing in front of you — is not a settings errand.
  static const team = '/team';
  static const managerLog = '/manager-log';
  static const printing = '/printing';

  /// Settings. A hub of pushed leaves rather than the web's six tabs — see
  /// `features/settings/settings_hub_screen.dart` for why.
  static const settings = '/settings';
  static const settingsGeneral = '/settings/general';
  static const settingsCharges = '/settings/charges';
  static const settingsReceipt = '/settings/receipt';
  static const settingsBranches = '/settings/branches';
  static const settingsPrinters = '/settings/printers';
  static const settingsPlan = '/settings/plan';
  static const settingsProfile = '/settings/profile';
  static const settingsAppearance = '/settings/appearance';
  static const settingsDanger = '/settings/danger';
  static const settingsDangerReset = '/settings/danger/reset';
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
  //
  // Dismissing the welcome carousel is none of those — it is not an auth state
  // change at all — so it needs its own bump, or the screen sets the flag and
  // nothing moves.
  ref
    ..listen(authStateProvider, (_, _) => refresh.value++)
    ..listen(membershipsProvider, (_, _) => refresh.value++)
    ..listen(permissionsProvider, (_, _) => refresh.value++)
    ..listen(welcomeSeenProvider, (_, _) => refresh.value++)
    ..onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: Routes.home,
    refreshListenable: refresh,
    redirect: (context, state) => resolveRedirect(
      signedIn: ref.read(currentUserProvider) != null,
      memberships: ref.read(membershipsProvider),
      permissions: ref.read(permissionsProvider).valueOrNull,
      location: state.matchedLocation,
      welcomeSeen: ref.read(welcomeSeenProvider),
    ),
    routes: [
      GoRoute(
        path: Routes.home,
        builder: (context, state) => const HomeShell(),
      ),
      GoRoute(
        path: Routes.welcome,
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: Routes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: Routes.signup,
        builder: (context, state) => const SignupScreen(),
      ),
      GoRoute(
        path: Routes.verify,
        builder: (context, state) =>
            VerifyEmailScreen(email: state.uri.queryParameters['email'] ?? ''),
      ),
      GoRoute(
        path: Routes.join,
        builder: (context, state) => const OnboardingScreen(),
      ),
      // Drawer destinations. Real routes rather than imperative pushes, so the
      // drawer can say which one you are on without tracking it itself.
      GoRoute(path: Routes.kds, builder: (context, state) => const KdsScreen()),
      GoRoute(
        path: Routes.dashboard,
        builder: (context, state) => const DashboardScreen(),
      ),
      GoRoute(
        path: Routes.dayClose,
        builder: (context, state) => const DayCloseScreen(),
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
        path: Routes.team,
        builder: (context, state) => const TeamScreen(),
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
      // Settings. Nested so the sub-screens are leaves of one destination —
      // back from any of them lands on the hub, and the drawer highlights
      // Settings the whole way down.
      //
      // No permission branch in the redirect, for the reason spelled out on the
      // bill route below: it resolves before permissions load and would bounce
      // an owner off their own settings. Each row is gated where it is drawn,
      // and every write behind it is gated again by RLS.
      GoRoute(
        path: Routes.settings,
        builder: (context, state) => const SettingsHubScreen(),
        routes: [
          GoRoute(
            path: 'general',
            builder: (context, state) => const GeneralSettingsScreen(),
          ),
          GoRoute(
            path: 'charges',
            builder: (context, state) => const ChargesSettingsScreen(),
          ),
          GoRoute(
            path: 'receipt',
            builder: (context, state) => const ReceiptSettingsScreen(),
          ),
          GoRoute(
            path: 'branches',
            builder: (context, state) => const BranchesScreen(),
          ),
          GoRoute(
            path: 'printers',
            builder: (context, state) => const PrintersScreen(),
          ),
          GoRoute(
            path: 'plan',
            builder: (context, state) => const PlanUsageScreen(),
          ),
          GoRoute(
            path: 'profile',
            builder: (context, state) => const ProfileScreen(),
          ),
          GoRoute(
            path: 'appearance',
            builder: (context, state) => const AppearanceScreen(),
          ),
          GoRoute(
            path: 'danger',
            builder: (context, state) => const DangerScreen(),
            routes: [
              GoRoute(
                path: 'reset',
                builder: (context, state) => const DangerResetScreen(),
              ),
            ],
          ),
        ],
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
