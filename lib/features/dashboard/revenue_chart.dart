import 'package:flutter/material.dart';

import '../../core/format/money.dart';
import '../../core/theme/app_theme.dart';
import '../../data/supabase/dashboard_repository.dart';

/// Revenue over the window, drawn rather than plotted.
///
/// No charting package: this is one series of at most 90 zero-filled points
/// with no axes, no legend and no interaction, and every drawing dependency
/// brings its own idea of colour and type. A `CustomPainter` reads the same
/// theme tokens as the rest of the app.
///
/// Colour is never the message here — the peak carries a dot and a printed
/// figure, and the ends print their dates, so the chart survives greyscale.
class RevenueChart extends StatelessWidget {
  const RevenueChart({
    required this.series,
    required this.currency,
    super.key,
    this.height = 160,
  });

  final List<RevenueDay> series;
  final String currency;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (series.isEmpty) return const SizedBox.shrink();

    final peak = series.reduce(
      (a, b) => b.revenueCents > a.revenueCents ? b : a,
    );
    final total = series.fold<int>(0, (sum, d) => sum + d.revenueCents);

    return Semantics(
      label:
          'Revenue chart, ${series.length} days. '
          'Total ${money(total, currency)}. '
          'Best day ${peak.label}, ${money(peak.revenueCents, currency)}.',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: height,
            width: double.infinity,
            child: CustomPaint(
              painter: _RevenuePainter(
                series: series,
                line: theme.colorScheme.primary,
                fill: theme.colorScheme.primary.withValues(alpha: 0.14),
                grid: theme.dividerColor,
                dot: theme.colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 6),
          // The ends of the window and the peak, in text — a chart nobody can
          // read a number off is decoration.
          Row(
            children: [
              Text(series.first.label, style: theme.textTheme.labelSmall),
              const Spacer(),
              if (peak.revenueCents > 0) ...[
                Icon(Icons.circle, size: 7, color: theme.colorScheme.primary),
                const SizedBox(width: 4),
                Text(
                  'Peak ${peak.label} · ${money(peak.revenueCents, currency)}',
                  style: theme.textTheme.labelSmall?.tabular,
                ),
                const Spacer(),
              ],
              Text(series.last.label, style: theme.textTheme.labelSmall),
            ],
          ),
        ],
      ),
    );
  }
}

class _RevenuePainter extends CustomPainter {
  const _RevenuePainter({
    required this.series,
    required this.line,
    required this.fill,
    required this.grid,
    required this.dot,
  });

  final List<RevenueDay> series;
  final Color line;
  final Color fill;
  final Color grid;
  final Color dot;

  @override
  void paint(Canvas canvas, Size size) {
    if (series.isEmpty || size.width <= 0 || size.height <= 0) return;

    const padTop = 10.0;
    const padBottom = 4.0;
    final plotHeight = (size.height - padTop - padBottom).clamp(
      1.0,
      size.height,
    );

    var maxCents = 0;
    for (final d in series) {
      if (d.revenueCents > maxCents) maxCents = d.revenueCents;
    }
    // An all-zero window still draws its baseline rather than dividing by zero.
    final scale = maxCents == 0 ? 0.0 : plotHeight / maxCents;

    final dx = series.length == 1 ? 0.0 : size.width / (series.length - 1);
    Offset pointAt(int i) => Offset(
      series.length == 1 ? size.width / 2 : i * dx,
      padTop + plotHeight - series[i].revenueCents * scale,
    );

    // Baseline: without it a flat zero window looks like a rendering failure.
    canvas.drawLine(
      Offset(0, size.height - padBottom),
      Offset(size.width, size.height - padBottom),
      Paint()
        ..color = grid
        ..strokeWidth = 1,
    );

    final path = Path()..moveTo(pointAt(0).dx, pointAt(0).dy);
    for (var i = 1; i < series.length; i++) {
      final p = pointAt(i);
      path.lineTo(p.dx, p.dy);
    }

    final area = Path.from(path)
      ..lineTo(pointAt(series.length - 1).dx, size.height - padBottom)
      ..lineTo(pointAt(0).dx, size.height - padBottom)
      ..close();

    canvas.drawPath(area, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    if (maxCents > 0) {
      final peakIndex = series.indexWhere((d) => d.revenueCents == maxCents);
      final p = pointAt(peakIndex);
      canvas
        ..drawCircle(p, 5, Paint()..color = dot)
        ..drawCircle(
          p,
          5,
          Paint()
            ..color = grid
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
    }
  }

  @override
  bool shouldRepaint(_RevenuePainter old) =>
      old.series != series || old.line != line || old.fill != fill;
}
