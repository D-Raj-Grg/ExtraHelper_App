import 'package:flutter/widgets.dart';

/// Width breakpoints, in logical pixels.
///
/// The app ships universal, so the same widgets render on a 320dp phone and a
/// 1024dp+ iPad. These are the only widths layout code should branch on, so a
/// screen never invents its own "tablet" number. The names follow Material 3's
/// window size classes.
///
/// **Phones stay exactly as they were.** Nothing in this file changes anything
/// below [compact]'s upper bound: every helper in `core/layout/` is a no-op at
/// phone width by construction.
abstract final class Breakpoints {
  /// Upper bound (exclusive) of a phone in portrait.
  static const double compact = 600;

  /// Upper bound (exclusive) of [WindowSize.medium] — an iPad in portrait.
  static const double expanded = 840;

  /// The width a column of reading content (forms, lists, settings) is capped
  /// at. Wider than a phone, narrower than a line length that is tiring to scan.
  static const double reading = 720;

  /// The cap for surfaces that really use width — a board of tables — but still
  /// should not stretch across a 12.9" landscape.
  static const double wide = 1100;

  /// Below this a master/detail layout stacks instead of sitting side by side.
  /// Chosen so an iPad mini in portrait (744dp) already gets two panes.
  static const double twoPane = 720;
}

/// Material 3 window size classes, by width.
enum WindowSize {
  /// Phones in portrait.
  compact,

  /// Large phones in landscape, iPads in portrait.
  medium,

  /// iPads in landscape, desktops.
  expanded;

  static WindowSize of(double width) => width < Breakpoints.compact
      ? compact
      : (width < Breakpoints.expanded ? medium : expanded);
}

extension WindowSizeContext on BuildContext {
  /// The window size class of the whole screen. For a widget that should react
  /// to the room it was *given* rather than the screen, use a `LayoutBuilder`.
  WindowSize get windowSize => WindowSize.of(MediaQuery.sizeOf(this).width);
}
