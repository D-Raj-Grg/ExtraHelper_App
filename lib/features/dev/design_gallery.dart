import 'package:flutter/material.dart';

import '../../app/app_scaffold.dart';
import '../../core/format/labels.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/choice_chip.dart';
import '../../core/widgets/menu_tile.dart';
import '../../core/widgets/table_glyph.dart';
import '../../core/widgets/veg_mark.dart';

/// Debug-only gallery of the ported design system.
///
/// Exists so the "never colour alone" rule is **checkable**: screenshot this
/// screen, apply greyscale, and every state must still be readable. That check
/// is hard to do against real screens, where a given state may take minutes of
/// setup to reach.
///
/// Reachable only in debug builds — see the router.
class DesignGallery extends StatefulWidget {
  const DesignGallery({super.key});

  @override
  State<DesignGallery> createState() => _DesignGalleryState();
}

class _DesignGalleryState extends State<DesignGallery> {
  String _selectedState = 'occupied';

  static const _states = [
    'free',
    'occupied',
    'reserved',
    'bill_requested',
    'cleaning',
  ];

  Color _stateColor(BuildContext context, String state) {
    final s = context.semantic;
    return switch (state) {
      'free' => s.goodText,
      'occupied' => s.warningText,
      'reserved' => s.infoText,
      'bill_requested' => s.attentionText,
      _ => s.neutral,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppScaffold(
      title: 'Design system',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Section(
            title: 'Veg marks',
            note:
                'Circle vs triangle carries the meaning. Unmarked renders nothing.',
            child: Row(
              children: [
                const VegMark(isVeg: true, size: 20),
                const SizedBox(width: 12),
                const VegMark(isVeg: false, size: 20),
                const SizedBox(width: 12),
                const VegMark(size: 20),
                const SizedBox(width: 12),
                Text(
                  'veg · non-veg · unmarked',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          _Section(
            title: 'Table states',
            note: 'Colour + label + fill. Solid seats = occupied.',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final state in _states)
                  AppChoiceChip(
                    label: 'T${_states.indexOf(state) + 1}',
                    detail: tableStateLabel(state),
                    selected: _selectedState == state,
                    showCheck: true,
                    statusColor: _stateColor(context, state),
                    onSelect: () => setState(() => _selectedState = state),
                    leading: TableGlyph(
                      seats: _states.indexOf(state) + 2,
                      filled: state == 'occupied' || state == 'bill_requested',
                      size: 26,
                    ),
                  ),
              ],
            ),
          ),
          _Section(
            title: 'Order + bill labels',
            note: 'Enum values never reach staff.',
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final s in ['draft', 'in_kitchen', 'ready', 'billed'])
                  Chip(label: Text(orderStatusLabel(s))),
                for (final s in ['open', 'partial', 'paid'])
                  Chip(label: Text(billStatusLabel(s))),
                for (final t in ['dine_in', 'pickup', 'qr'])
                  Chip(label: Text(orderTypeLabel(t))),
              ],
            ),
          ),
          _Section(
            title: 'Menu tiles',
            note:
                'Photo-first. Variant dishes show a price RANGE, not an unbuyable base price.',
            child: GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.78,
              children: [
                MenuTile(
                  name: 'Buff Sekuwa',
                  minPriceCents: 108000,
                  maxPriceCents: 168000,
                  currency: 'NPR',
                  isVeg: false,
                  optionCount: 3,
                  qtyInOrder: 2,
                  onTap: () {},
                ),
                MenuTile(
                  name: 'Dal Bhat',
                  minPriceCents: 45000,
                  maxPriceCents: 45000,
                  currency: 'NPR',
                  isVeg: true,
                  onTap: () {},
                ),
                MenuTile(
                  name: 'Aila (per shot)',
                  minPriceCents: 15000,
                  maxPriceCents: 15000,
                  currency: 'NPR',
                  soldOut: true,
                  onTap: () {},
                ),
                MenuTile(
                  name: 'Chicken Choila',
                  minPriceCents: 52000,
                  maxPriceCents: 52000,
                  currency: 'NPR',
                  onTap: () {},
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.note,
    required this.child,
  });

  final String title;
  final String note;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 2),
          Text(note, style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
