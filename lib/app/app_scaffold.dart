import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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

  @override
  Widget build(BuildContext context) {
    final scaffold = Scaffold(
      drawer: showDrawer ? const AppDrawer() : null,
      appBar: AppBar(
        // One line, always. Two lines in an app bar clip the moment someone
        // turns their text size up, and this app ships to people who do.
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: actions,
        bottom: bottom ?? _subtitleBar(context),
      ),
      body: Column(
        children: [
          const SyncStrip(),
          Expanded(child: body),
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
