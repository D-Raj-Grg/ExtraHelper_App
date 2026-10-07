import 'package:flutter/widgets.dart';

import 'breakpoints.dart';

/// Caps its child to [maxWidth] and centres it, when there is more room than
/// that. When there is not — every phone — it returns the child untouched, so
/// the widget tree and the layout are exactly what they were without it.
///
/// With [fillHeight] (the default) the child is also handed the full height it
/// was offered, so a `Column` with an `Expanded` or a `ListView` inside keeps
/// working; the capped column just sits in the middle of the width. Set it false
/// for a content-sized child (a bar), which is top-aligned instead.
class MaxWidthBody extends StatelessWidget {
  const MaxWidthBody({
    super.key,
    required this.child,
    this.maxWidth = Breakpoints.reading,
    this.fillHeight = true,
  });

  final Widget child;
  final double maxWidth;
  final bool fillHeight;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth || constraints.maxWidth <= maxWidth) {
          return child;
        }
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: maxWidth,
            height: fillHeight && constraints.hasBoundedHeight
                ? constraints.maxHeight
                : null,
            child: child,
          ),
        );
      },
    );
  }
}
