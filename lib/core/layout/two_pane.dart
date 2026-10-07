import 'package:flutter/material.dart';

import 'breakpoints.dart';

/// A [primary] area with a [secondary] one beside it on a wide screen, and
/// stacked under it on a narrow one.
///
/// Narrow, this is `Column[Expanded(primary), secondary]` — the secondary sits
/// at its natural height, exactly like a bottom bar, which is what the order
/// composer's cart already was. Wide, it is a `Row` with the secondary as a
/// fixed-width side panel full height, separated by a hairline.
///
/// [secondary] is a builder because the two shapes usually differ in more than
/// placement: it is told whether it is [sideBySide] so it can drop a collapse
/// toggle that makes no sense in a panel that is always open.
///
/// The decision is on the width this widget is *given* (a `LayoutBuilder`), not
/// the screen's, so it still does the right thing in a split-view iPad window.
class TwoPane extends StatelessWidget {
  const TwoPane({
    super.key,
    required this.primary,
    required this.secondary,
    this.secondaryWidth = 360,
    this.minWidth = Breakpoints.twoPane,
  });

  final Widget primary;
  final Widget Function(BuildContext context, bool sideBySide) secondary;
  final double secondaryWidth;

  /// The least width at which the panes sit side by side.
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final sideBySide =
            constraints.hasBoundedWidth && constraints.maxWidth >= minWidth;
        if (!sideBySide) {
          return Column(
            children: [
              Expanded(child: primary),
              secondary(context, false),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: primary),
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: Theme.of(context).colorScheme.outline,
            ),
            SizedBox(width: secondaryWidth, child: secondary(context, true)),
          ],
        );
      },
    );
  }
}
