import 'package:flutter/material.dart';

/// The swatches a custom role can be given, mirroring the web's `ROLE_COLORS`.
///
/// Colour is decorative here — the role's name carries its identity — so every
/// swatch has a name a screen reader can announce, and selection in the editor
/// is drawn with a check rather than fill alone.
const kRoleColors = <({String hex, String name})>[
  (hex: '#059669', name: 'Emerald'),
  (hex: '#d97706', name: 'Amber'),
  (hex: '#7c3aed', name: 'Violet'),
  (hex: '#c026d3', name: 'Fuchsia'),
  (hex: '#2563eb', name: 'Blue'),
  (hex: '#16a34a', name: 'Green'),
  (hex: '#64748b', name: 'Slate'),
  (hex: '#ef4444', name: 'Red'),
  (hex: '#b91c1c', name: 'Dark red'),
  (hex: '#0a0a0a', name: 'Black'),
  (hex: '#78350f', name: 'Brown'),
  (hex: '#ec4899', name: 'Pink'),
];

/// The default the server writes when a role is created without one.
const kDefaultRoleColor = '#64748b';

/// A name for the swatch, for `Semantics`. Falls back to the hex rather than
/// staying silent — an unnamed dot announces as nothing at all.
String roleColorName(String hex) {
  final needle = hex.trim().toLowerCase();
  for (final swatch in kRoleColors) {
    if (swatch.hex == needle) return swatch.name;
  }
  return needle;
}

/// The parsed swatch. The repository already guarantees `#rrggbb`, so this
/// cannot throw; the fallback is here for a caller that skips it.
Color roleColor(String hex) {
  final needle = hex.trim().toLowerCase();
  final value = int.tryParse(needle.replaceFirst('#', ''), radix: 16);
  if (value == null) return const Color(0xff64748b);
  return Color(0xff000000 | value);
}
