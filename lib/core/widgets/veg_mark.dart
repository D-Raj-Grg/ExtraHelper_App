import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// The veg / non-veg mark used across South Asia.
///
/// **The shape carries the meaning; the colour only reinforces it.** A green
/// dot vs a red dot is indistinguishable to the most common colourblindness,
/// and "never colour alone" is a house rule for exactly this reason — so veg is
/// a **circle** and non-veg a **triangle**, which is also the real convention.
/// Both survive a greyscale screenshot.
///
/// A null [isVeg] renders nothing. `menu_items.is_veg` is nullable on purpose:
/// unmarked is a real state, and mislabelling food is worse than not labelling
/// it.
class VegMark extends StatelessWidget {
  const VegMark({super.key, this.isVeg, this.size = 14});

  final bool? isVeg;
  final double size;

  @override
  Widget build(BuildContext context) {
    final veg = isVeg;
    if (veg == null) return const SizedBox.shrink();

    final semantic = context.semantic;
    final color = veg ? semantic.goodText : semantic.danger;
    final label = veg ? 'Vegetarian' : 'Non-vegetarian';

    return Semantics(
      label: label,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          border: Border.all(color: color, width: 1.5),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Center(
          child: veg
              ? Container(
                  width: size * 0.42,
                  height: size * 0.42,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                )
              // A triangle, not a dot — this is the part that survives
              // greyscale.
              : CustomPaint(
                  size: Size(size * 0.5, size * 0.44),
                  painter: _TrianglePainter(color),
                ),
        ),
      ),
    );
  }
}

class _TrianglePainter extends CustomPainter {
  const _TrianglePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_TrianglePainter oldDelegate) =>
      oldDelegate.color != color;
}
