import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/layout/breakpoints.dart';
import '../core/layout/max_width_body.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/tenant/app_drawer.dart';
import '../features/tenant/sync_status_bar.dart';
import 'router.dart';

/// The frame every signed-in surface renders inside.
///
/// One widget owns the chrome so it cannot drift screen to screen: the drawer
/// hangs here, the sync strip sits directly above the body here, and the title
/// is one line here. Before this, each screen built its own `Scaffold` and the
/// root one carried six destination icons in the app bar — 264px of actions on
/// a 360dp phone, in the corner a waiter holding a tray can least reach.
///
/// * [showDrawer] false for a leaf that was pushed on top of a destination
///   (stock count, composer): those keep the back arrow.
/// * [showBell] false on the feed itself. The bell draws nothing for anyone
///   without `notifications.view`, so it is safe to leave on everywhere else.
/// * [subtitle] renders under the title at a height derived from the user's
///   text scale, never a hardcoded one.
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    required this.title,
    required this.body,
    this.subtitle,
    this.actions,
    this.bottom,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.showDrawer = true,
    this.showBell = true,
    this.maxBodyWidth = Breakpoints.reading,
  });

  final String title;

  /// Context for the surface — the restaurant's timezone, the order's table.
  /// Ignored when [bottom] is given; a bar has room for one or the other.
  final String? subtitle;

  final Widget body;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final bool showDrawer;
  final bool showBell;

  /// The widest the body gets before it is centred. The default suits lists and
  /// forms, which read as a stretched phone on an iPad. Pass [Breakpoints.wide]
  /// for a surface that genuinely uses width, or null for one that lays itself
  /// out against the full width (the kitchen board, the dashboard). Below this
  /// width — every phone — it changes nothing. The app bar and sync strip always
  /// span the full width.
  final double? maxBodyWidth;

  @override
  Widget build(BuildContext context) {
    final scaffold = Scaffold(
      drawer: showDrawer ? const AppDrawer() : null,
      appBar: AppBar(
        // One line, always. Two lines in an app bar clip the moment someone
        // turns their text size up, and this app ships to people who do.
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        // The bell goes last, in the corner every app puts it.
        actions: [...?actions, if (showBell) const NotificationBell()],
        bottom: bottom ?? _subtitleBar(context),
      ),
      body: Column(
        children: [
          const SyncStrip(),
          Expanded(
            child: maxBodyWidth == null
                ? body
                : MaxWidthBody(maxWidth: maxBodyWidth!, child: body),
          ),
        ],
      ),
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar,
    );

    if (!showDrawer) return scaffold;

    // Destinations replace rather than stack, so there is no route to pop back
    // to. Back belongs to the POS — it is the surface someone came here from
    // and the one they need in a hurry.
    final atHome = GoRouterState.of(context).matchedLocation == Routes.home;
    return PopScope(
      canPop: atHome,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) GoRouter.of(context).go(Routes.home);
      },
      child: scaffold,
    );
  }

  PreferredSizeWidget? _subtitleBar(BuildContext context) {
    final text = subtitle;
    if (text == null) return null;
    final style = Theme.of(context).textTheme.bodySmall;
    final height =
        MediaQuery.textScalerOf(context).scale(style?.fontSize ?? 12) * 1.45 +
        10;
    return PreferredSize(
      preferredSize: Size.fromHeight(height),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      ),
    );
  }
}
