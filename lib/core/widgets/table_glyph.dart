import 'package:flutter/material.dart';

/// A top-down diagram of a table: the surface, plus one seat per cover.
///
/// Seat count is the capacity, so the number beside it has a shape to match —
/// and the fill carries the state without leaning on hue: an occupied table's
/// seats are solid, a free table's are hollow. Passes a greyscale screenshot.
///
/// Ported from the web's `components/pos/table-glyph.tsx`; the layout maths is
/// deliberately identical so the two clients draw the same table.
class TableGlyph extends StatelessWidget {
  const TableGlyph({
    super.key,
    required this.seats,
    required this.filled,
    this.size = 48,
    this.color,
  });

  final int seats;
  final bool filled;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _TableGlyphPainter(
        seats: seats,
        filled: filled,
        color:
            color ?? DefaultTextStyle.of(context).style.color ?? Colors.black,
      ),
    );
  }
}

class _TableGlyphPainter extends CustomPainter {
  const _TableGlyphPainter({
    required this.seats,
    required this.filled,
    required this.color,
  });

  final int seats;
  final bool filled;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // The web draws on a 48x48 viewBox; scale so the geometry constants below
    // stay readable against the original.
    final s = size.width / 48;

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5 * s;
    final fill = Paint()..color = color.withValues(alpha: 0.14);

    final surface = RRect.fromRectAndRadius(
      Rect.fromLTWH(13 * s, 13 * s, 22 * s, 22 * s),
      Radius.circular(6 * s),
    );
    if (filled) canvas.drawRRect(surface, fill);
    canvas.drawRRect(surface, stroke);

    // Beyond eight the seats stop being countable at this size; the numeric
    // label beside the glyph stays authoritative either way.
    final n = seats <= 0 ? 2 : (seats > 8 ? 8 : seats);

    // Round-robin the covers onto the four sides, so a 4-top reads as one per
    // side and a 6-top puts the extras on the long edges.
    final sides = <int>[0, 0, 0, 0];
    for (var i = 0; i < n; i++) {
      sides[i % 4] += 1;
    }

    double spread(int count, int i) => 14 + (20 * (i + 1)) / (count + 1);

    final seatStroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * s;
    final seatFill = Paint()..color = color;

    void seat(double x, double y, double w, double h) {
      final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(x * s, y * s, w * s, h * s),
        Radius.circular(2.25 * s),
      );
      if (filled) canvas.drawRRect(r, seatFill);
      canvas.drawRRect(r, seatStroke);
    }

    final [top, bottom, left, right] = sides;
    for (var i = 0; i < top; i++) {
      seat(spread(top, i) - 4, 5, 8, 4.5);
    }
    for (var i = 0; i < bottom; i++) {
      seat(spread(bottom, i) - 4, 38.5, 8, 4.5);
    }
    for (var i = 0; i < left; i++) {
      seat(5, spread(left, i) - 4, 4.5, 8);
    }
    for (var i = 0; i < right; i++) {
      seat(38.5, spread(right, i) - 4, 4.5, 8);
    }
  }

  @override
  bool shouldRepaint(_TableGlyphPainter old) =>
      old.seats != seats || old.filled != filled || old.color != color;
}
