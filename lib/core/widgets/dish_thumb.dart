import 'package:flutter/material.dart';

/// Initials for the placeholder — "Buff Sekuwa" → "BS", "Aila (per shot)" → "A".
/// Parenthetical qualifiers are noise here, so they're dropped before picking.
///
/// Ported verbatim from the web's `dish-thumb.tsx` so a photoless dish shows the
/// same initials on both clients.
String monogram(String name) {
  final words = name
      .replaceAll(RegExp(r'\([^)]*\)'), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => RegExp('[a-z0-9]', caseSensitive: false).hasMatch(w))
      .toList();
  if (words.isEmpty) return '?';
  return words.take(2).map((w) => w.isEmpty ? '' : w[0].toUpperCase()).join();
}

/// A dish's photo, or a designed absence when it has none.
///
/// Shared by the tile and the options sheet so "what a photoless dish looks
/// like" is decided once — a second placeholder that drifted from this one
/// would be obvious the moment they sat side by side.
class DishThumb extends StatelessWidget {
  const DishThumb({
    super.key,
    required this.name,
    this.imageUrl,
    this.monogramSize = 30,
  });

  final String name;
  final String? imageUrl;
  final double monogramSize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final url = imageUrl;

    if (url != null && url.isNotEmpty) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        // A dish whose photo fails to load must still look deliberate, not
        // broken — fall back to the same designed placeholder.
        errorBuilder: (context, _, _) => _placeholder(scheme),
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : _placeholder(scheme),
      );
    }
    return _placeholder(scheme);
  }

  Widget _placeholder(ColorScheme scheme) {
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Center(
        child: Text(
          monogram(name),
          style: TextStyle(
            fontSize: monogramSize,
            fontWeight: FontWeight.w700,
            fontVariations: const [FontVariation('wght', 700)],
            color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
            letterSpacing: -0.5,
          ),
        ),
      ),
    );
  }
}
