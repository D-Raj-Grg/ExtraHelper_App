import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/table_glyph.dart';

/// The four drawings on the welcome carousel.
///
/// Drawn, not shipped: the app bundles one font and nothing else, and a staff
/// app must render itself on dead wifi. No illustration package either — every
/// one of them brings its own idea of colour and type.
///
/// Each obeys the house rule the rest of the app obeys: **shape carries the
/// meaning, colour only reinforces it.** Filled versus outlined, solid versus
/// dashed, hatched versus plain — all of it survives a greyscale screenshot,
/// which is the check `/dev/design` exists for. Every fill is a `colorScheme`
/// role or a `context.semantic` tone, so dark is first-class rather than an
/// afterthought.
///
/// These are decoration. The headline beside each one carries the message, so
/// they are wrapped in [ExcludeSemantics] and the screen drops them entirely at
/// large text sizes.

/// Common frame: a 4:3 box, with the drawing composed at its **own** size and
/// then scaled down to fit.
///
/// The alternative — letting each vignette lay itself out against whatever
/// width it is handed — looks fine until something inside it measures wider
/// than expected, and then a `Row` overflows and Flutter clips it. Two things
/// move that width and neither is under this file's control: the text scale the
/// phone is set to, and the metrics of whatever font is actually resolved.
/// Slide 2's row of tabs overflowed by 82px on a 320px phone at *normal* text
/// size for exactly that reason.
///
/// Scaling is the right answer **here specifically** because this is
/// decoration: the headline beside it carries the message, and these are
/// wrapped in [ExcludeSemantics] precisely because nothing in them needs to be
/// read. Real content still grows with the user's text size — and past a point
/// the slide drops the art entirely rather than shrink the sentence.
class _ArtFrame extends StatelessWidget {
  const _ArtFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: FittedBox(fit: BoxFit.scaleDown, child: child),
      ),
    );
  }
}

/// Slide 1 — orders waiting out a dead spot.
///
/// Three tickets, three different marks: a **filled** check badge (sent), an
/// **outlined** clock badge (queued), and a **dashed** outline (still being
/// written). Nothing here needs colour to be read.
class OfflineQueueArt extends StatelessWidget {
  const OfflineQueueArt({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantic = context.semantic;

    return _ArtFrame(
      // A fixed composition width: the frame scales it, so this is the drawing's
      // own proportions rather than a guess at the space available.
      child: SizedBox(
        width: 260,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: scheme.outlineVariant),
                  borderRadius: BorderRadius.circular(Tokens.radiusSm),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.wifi_off,
                      size: 14,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text('Offline', style: theme.textTheme.labelSmall),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _Ticket(
              badge: _Badge(
                icon: Icons.check,
                tone: semantic.goodText,
                filled: true,
              ),
              dashed: false,
            ),
            const SizedBox(height: 8),
            _Ticket(
              badge: _Badge(
                icon: Icons.schedule,
                tone: semantic.warningText,
                filled: false,
              ),
              dashed: false,
            ),
            const SizedBox(height: 8),
            _Ticket(badge: null, dashed: true),
          ],
        ),
      ),
    );
  }
}

class _Ticket extends StatelessWidget {
  const _Ticket({required this.badge, required this.dashed});

  final Widget? badge;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final inner = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Bar(widthFactor: 0.62),
                const SizedBox(height: 6),
                _Bar(widthFactor: 0.38),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ?badge,
        ],
      ),
    );

    if (dashed) {
      return CustomPaint(
        painter: _DashedBorderPainter(
          color: scheme.outlineVariant,
          radius: Tokens.radiusMd,
        ),
        child: inner,
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(Tokens.radiusMd),
      ),
      child: inner,
    );
  }
}

/// A stand-in for a line of text. Never real words: a drawing that spells
/// something is a drawing that has to be translated.
class _Bar extends StatelessWidget {
  const _Bar({required this.widthFactor, this.height = 7, this.strong = false});

  final double widthFactor;
  final double height;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: strong ? scheme.onSurfaceVariant : scheme.outlineVariant,
          borderRadius: BorderRadius.circular(Tokens.radiusSm),
        ),
      ),
    );
  }
}

/// Filled or outlined, plus its own glyph. Two signals, so the tone is the
/// third and least of them.
class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.tone, required this.filled});

  final IconData icon;
  final Color tone;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? tone : Colors.transparent,
        border: Border.all(color: tone, width: 1.5),
      ),
      child: Icon(
        icon,
        size: 13,
        color: filled ? Theme.of(context).colorScheme.surface : tone,
      ),
    );
  }
}

/// Slide 2 — the floor.
///
/// Real [TableGlyph]s, not a second drawing of a table: solid seats mean
/// occupied and hollow ones free, which is the convention the POS board already
/// teaches and which already passes greyscale.
class FloorArt extends StatelessWidget {
  const FloorArt({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantic = context.semantic;

    const tables = [
      (4, true),
      (2, false),
      (6, true),
      (2, false),
      (4, false),
      (8, true),
    ];

    return _ArtFrame(
      // Bounded on purpose: the `Wrap` below has no width to wrap against
      // otherwise, because a `FittedBox` hands its child unbounded constraints.
      child: SizedBox(
        width: 250,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Wrap, not Row: four labels laid across a fixed width is a bet on
            // how wide those four words render, and that changes with the text
            // scale and with whichever font actually resolves. A Row loses that
            // bet by clipping; a Wrap loses it by taking a second line.
            Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: [
                for (final (i, label) in [
                  'Tables',
                  'Orders',
                  'Bills',
                  'Done',
                ].indexed)
                  _Pill(label: label, active: i == 0),
              ],
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 18,
              runSpacing: 14,
              alignment: WrapAlignment.center,
              children: [
                for (final (seats, filled) in tables)
                  TableGlyph(
                    seats: seats,
                    filled: filled,
                    size: 42,
                    color: filled
                        ? semantic.warningText
                        : scheme.onSurfaceVariant,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Filled **and** underlined when active, outlined when not — the same
/// belt-and-braces the app's own selected states use.
class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: active ? scheme.primary : Colors.transparent,
            border: Border.all(
              color: active ? scheme.primary : scheme.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(Tokens.radiusSm),
          ),
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: active ? scheme.onPrimary : scheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          height: 2,
          width: 18,
          color: active ? scheme.primary : Colors.transparent,
        ),
      ],
    );
  }
}

/// Slide 3 — the day's figures, and the day shut.
///
/// Four days closed and drawn solid, today still open and drawn **hatched**.
/// Hatching is the most greyscale-proof mark there is, and it says "not final"
/// without needing a legend.
const _dayCloseWidth = 240.0;

class DayCloseArt extends StatelessWidget {
  const DayCloseArt({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantic = context.semantic;

    return _ArtFrame(
      child: SizedBox(
        width: _dayCloseWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.arrow_upward, size: 15, color: semantic.goodText),
                const SizedBox(width: 4),
                Expanded(child: _Bar(widthFactor: 0.5, strong: true)),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 88,
              child: CustomPaint(
                size: const Size(_dayCloseWidth, 88),
                painter: _BarsPainter(
                  // Ascending, with the last one still running.
                  values: const [0.42, 0.55, 0.5, 0.78, 0.62],
                  solid: scheme.primary,
                  hatch: scheme.onSurfaceVariant,
                  baseline: theme.dividerColor,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: scheme.outlineVariant),
                    borderRadius: BorderRadius.circular(Tokens.radiusSm),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.lock_outline,
                        size: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 5),
                      Text('Day closed', style: theme.textTheme.labelSmall),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Slide 4 — paper, off this device.
///
/// The torn zig-zag edge and the printer silhouette are pure shape; remove
/// every colour and it is still obviously a receipt coming out of a printer.
class PrintArt extends StatelessWidget {
  const PrintArt({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return _ArtFrame(
      child: SizedBox(
        width: 190,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The printer: a body with a slot the paper leaves by.
            Container(
              height: 54,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                border: Border.all(color: scheme.outlineVariant),
                borderRadius: BorderRadius.circular(Tokens.radiusMd),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: scheme.onSurfaceVariant),
                    ),
                    child: Icon(
                      Icons.bluetooth,
                      size: 13,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: 96,
                    height: 6,
                    decoration: BoxDecoration(
                      color: scheme.onSurfaceVariant,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
              ),
            ),
            // The slip, emerging. Narrower than the printer so it reads as
            // coming *out* of it rather than sitting under it.
            SizedBox(
              width: 132,
              child: CustomPaint(
                painter: _SlipPainter(
                  fill: scheme.surface,
                  border: scheme.outlineVariant,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 26),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Bar(widthFactor: 0.85, height: 6),
                      const SizedBox(height: 6),
                      _Bar(widthFactor: 0.6, height: 6),
                      const SizedBox(height: 6),
                      _Bar(widthFactor: 0.72, height: 6),
                      const SizedBox(height: 8),
                      Container(height: 1, color: scheme.outlineVariant),
                      const SizedBox(height: 8),
                      _Bar(widthFactor: 0.5, height: 8, strong: true),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A rounded rectangle drawn as dashes. Flutter has no dashed border, and the
/// distinction is load-bearing here: dashed means "not sent yet".
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      );

    const dash = 5.0;
    const gap = 4.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(
            distance,
            math.min(distance + dash, metric.length),
          ),
          paint,
        );
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}

/// Ascending bars, the last one hatched because the day it stands for is not
/// finished. Height is the figure; the hatch is the state.
class _BarsPainter extends CustomPainter {
  const _BarsPainter({
    required this.values,
    required this.solid,
    required this.hatch,
    required this.baseline,
  });

  final List<double> values;
  final Color solid;
  final Color hatch;
  final Color baseline;

  @override
  void paint(Canvas canvas, Size size) {
    final rule = Paint()
      ..color = baseline
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      rule,
    );

    final slot = size.width / values.length;
    final barWidth = slot * 0.58;

    for (final (i, value) in values.indexed) {
      final height = size.height * value;
      final left = i * slot + (slot - barWidth) / 2;
      final rect = RRect.fromRectAndCorners(
        Rect.fromLTWH(left, size.height - height, barWidth, height),
        topLeft: const Radius.circular(3),
        topRight: const Radius.circular(3),
      );

      final last = i == values.length - 1;
      if (!last) {
        canvas.drawRRect(rect, Paint()..color = solid);
        continue;
      }

      // Today: outlined and hatched rather than filled, so "still running"
      // reads without a legend and without a hue.
      canvas
        ..drawRRect(
          rect,
          Paint()
            ..color = hatch
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        )
        ..save()
        ..clipRRect(rect);

      final stroke = Paint()
        ..color = hatch
        ..strokeWidth = 1.2;
      for (var x = rect.left - rect.height; x < rect.right; x += 6) {
        canvas.drawLine(
          Offset(x, rect.bottom),
          Offset(x + rect.height, rect.top),
          stroke,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.values != values || old.solid != solid || old.hatch != hatch;
}

/// A receipt: square at the top where it leaves the printer, torn at the
/// bottom. The zig-zag is the whole illustration — without it this is a card.
class _SlipPainter extends CustomPainter {
  const _SlipPainter({required this.fill, required this.border});

  final Color fill;
  final Color border;

  @override
  void paint(Canvas canvas, Size size) {
    const tooth = 9.0;
    const toothHeight = 7.0;
    final bottom = size.height;

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, bottom - toothHeight);

    var x = size.width;
    var up = false;
    while (x > 0) {
      x = math.max(0, x - tooth);
      path.lineTo(x, up ? bottom - toothHeight : bottom);
      up = !up;
    }
    path.close();

    canvas
      ..drawPath(path, Paint()..color = fill)
      ..drawPath(
        path,
        Paint()
          ..color = border
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
  }

  @override
  bool shouldRepaint(_SlipPainter old) =>
      old.fill != fill || old.border != border;
}
