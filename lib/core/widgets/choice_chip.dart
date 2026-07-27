import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// A chip a waiter picks mid-service: few options, big target, unambiguous
/// selection.
///
/// Ported from the web's `components/pos/choice-chip.tsx`. Two things carry
/// over deliberately:
///
/// * **Minimum height 44** — this gets hit one-handed, in a hurry.
/// * **Selection is never carried by fill colour alone.** [showCheck] draws a
///   check on the selected chip, and [detail] carries the word, so the state
///   survives greyscale and colourblindness.
///
/// The web version wraps a real `<input type=radio>` for keyboard and screen
/// reader semantics; the Flutter equivalent is `Semantics(selected:)` on a
/// button, which is what the platform accessibility APIs expect here.
class AppChoiceChip extends StatelessWidget {
  const AppChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelect,
    this.detail,
    this.leading,
    this.statusColor,
    this.showCheck = false,
    this.enabled = true,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelect;

  /// The word under the label. Where [statusColor] is used, this is what
  /// actually communicates the state.
  final String? detail;

  /// Artwork ahead of the text — a glyph or icon. Inherits the chip's colour.
  final Widget? leading;

  /// A leading state dot. Never the only signal — [detail] carries the word.
  final Color? statusColor;

  /// Draw a check on the selected chip, so selection isn't fill colour alone.
  final bool showCheck;

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final background = selected ? scheme.primary : scheme.surfaceContainerLow;
    final foreground = selected ? scheme.onPrimary : scheme.onSurface;
    final borderColor = selected ? scheme.primary : scheme.outline;

    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: detail == null ? label : '$label, $detail',
      child: ExcludeSemantics(
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: Material(
            color: background,
            borderRadius: BorderRadius.circular(Tokens.radiusMd),
            child: InkWell(
              onTap: enabled ? onSelect : null,
              borderRadius: BorderRadius.circular(Tokens.radiusMd),
              child: Container(
                constraints: const BoxConstraints(minHeight: Tokens.tapTarget),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: borderColor, width: 2),
                  borderRadius: BorderRadius.circular(Tokens.radiusMd),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (leading != null) ...[
                      IconTheme(
                        data: IconThemeData(color: foreground),
                        child: DefaultTextStyle(
                          style: TextStyle(color: foreground),
                          child: leading!,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (statusColor != null) ...[
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          // A solid state hue disappears against the selected
                          // fill, so it flips to the foreground when selected.
                          color: selected ? foreground : statusColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Flexible(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: foreground,
                            ),
                          ),
                          if (detail != null)
                            Text(
                              detail!,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: selected
                                    ? foreground.withValues(alpha: 0.8)
                                    : scheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (showCheck && selected) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.check, size: 18, color: foreground),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
