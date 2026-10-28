import 'package:flutter/material.dart';

import '../format/money.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'dish_thumb.dart';
import 'veg_mark.dart';

/// One tappable dish. **Photo-first**: staff recognise a dish by its picture
/// faster than by reading it, so the image leads and the name and price sit
/// under it. The whole tile is the target — never a small button inside a card.
///
/// Ported from the web's `components/pos/menu-tile.tsx`, including the fix that
/// matters most: the tile shows the **price range**, not the base price. A dish
/// with variants forces a choice in the options sheet, so its base price is a
/// figure nobody can order — the web version once advertised NPR 380 when the
/// only orderable prices were 1,080 and 1,680. The range goes in the
/// accessibility label too.
class MenuTile extends StatelessWidget {
  const MenuTile({
    super.key,
    required this.name,
    required this.minPriceCents,
    required this.maxPriceCents,
    required this.currency,
    required this.onTap,
    this.onLongPress,
    this.imageUrl,
    this.isVeg,
    this.qtyInOrder = 0,
    this.soldOut = false,
    this.unavailableNow = false,
    this.availableAgain,
    this.disabled = false,
    this.optionCount = 0,
  });

  final String name;
  final int minPriceCents;
  final int maxPriceCents;
  final String currency;
  final VoidCallback onTap;

  /// Manager ops (86 a dish). Stays available when the tile is sold out —
  /// putting it *back* is the whole point.
  final VoidCallback? onLongPress;
  final String? imageUrl;
  final bool? isVeg;

  /// How many of this dish are already in the order. Shown as a count badge.
  final int qtyInOrder;

  final bool soldOut;

  /// Outside its availability window right now (server-judged). Not tappable;
  /// shown with a clock icon and [availableAgain] so it never reads as colour
  /// alone.
  final bool unavailableNow;

  /// "today 18:00" etc. — when it can be ordered again, if the server knows.
  final String? availableAgain;

  /// The order is fired/billed — the menu is visible but no longer addable.
  final bool disabled;

  /// Variants + add-ons. Above zero, tapping opens the picker instead of adding
  /// straight away, and the count is shown: "3 options" tells a waiter whether
  /// it's worth the tap; a bare "options" doesn't.
  final int optionCount;

  /// Photo width / height. The grid sizes its rows from this, so the tile has
  /// no dead space under the price.
  static const imageAspect = 1.45;

  /// Height of the name + price block at 1x text (two-line name allowed).
  static const textBlockHeight = 74.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final notNow = unavailableNow && !soldOut;
    final off = soldOut || notNow || disabled;
    final inCart = qtyInOrder > 0;
    final hasOptions = optionCount > 0;

    final priceText = moneyRange(minPriceCents, maxPriceCents, currency);

    final vegSuffix = switch (isVeg) {
      true => ', vegetarian',
      false => ', non-vegetarian',
      null => '',
    };
    final semanticLabel =
        '${hasOptions ? 'Choose options for' : 'Add'} $name, $priceText'
        '$vegSuffix${soldOut ? ', sold out' : ''}'
        '${notNow ? ', not available right now${availableAgain != null ? ', back $availableAgain' : ''}' : ''}'
        '${inCart ? ', $qtyInOrder in order' : ''}';

    return Semantics(
      button: true,
      enabled: !off,
      label: semanticLabel,
      child: ExcludeSemantics(
        // The border lives on the Material's shape: Material clips to it and
        // paints it over the children, so the photo can never cover the ring
        // at the corners.
        child: Material(
          color: scheme.surfaceContainerLow,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Tokens.radiusLg),
            side: BorderSide(
              color: inCart ? scheme.primary : scheme.outline,
              width: 2,
            ),
          ),
          child: InkWell(
            onTap: off ? null : onTap,
            onLongPress: onLongPress,
            // Dim the content, not the border, so a tile stays crisp.
            child: Opacity(
              opacity: off ? 0.6 : 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Stack(
                    children: [
                      AspectRatio(
                        aspectRatio: imageAspect,
                        child: DishThumb(name: name, imageUrl: imageUrl),
                      ),
                      if (inCart)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: _CountBadge(count: qtyInOrder),
                        ),
                      if (soldOut)
                        Positioned(
                          left: 6,
                          bottom: 6,
                          child: _Pill(
                            text: 'Sold out',
                            background: scheme.error,
                            foreground: scheme.onError,
                          ),
                        ),
                      if (notNow)
                        Positioned(
                          left: 6,
                          bottom: 6,
                          child: _Pill(
                            text: availableAgain != null
                                ? 'Back $availableAgain'
                                : 'Not now',
                            background: scheme.surface.withValues(alpha: 0.9),
                            foreground: scheme.onSurface,
                            icon: Icons.schedule,
                          ),
                        ),
                      if (hasOptions && !soldOut && !notNow)
                        Positioned(
                          left: 6,
                          bottom: 6,
                          child: _Pill(
                            text: '$optionCount options',
                            background: scheme.surface.withValues(alpha: 0.9),
                            foreground: scheme.onSurface,
                            icon: Icons.tune,
                          ),
                        ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (isVeg != null) ...[
                              VegMark(isVeg: isVeg),
                              const SizedBox(width: 6),
                            ],
                            Expanded(
                              child: Text(
                                name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          priceText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              (theme.textTheme.bodyMedium ?? const TextStyle())
                                  .tabular
                                  .copyWith(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Center(
        child: Text(
          '$count',
          style: TextStyle(
            color: scheme.onPrimary,
            fontWeight: FontWeight.w700,
            fontVariations: const [FontVariation('wght', 700)],
            fontFeatures: tabularFigures,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.text,
    required this.background,
    required this.foreground,
    this.icon,
  });

  final String text;
  final Color background;
  final Color foreground;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: foreground),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              color: foreground,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontVariations: const [FontVariation('wght', 600)],
            ),
          ),
        ],
      ),
    );
  }
}
