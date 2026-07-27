import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/format/money.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/choice_chip.dart';
import '../../core/widgets/dish_thumb.dart';
import '../../core/widgets/veg_mark.dart';
import 'models.dart';

/// Variant + add-ons + note + quantity for one dish.
///
/// A variant is **forced** when the dish has any: the first is preselected and
/// there is no "none" chip, because that's what the price on the tile promises.
/// Add-ons are optional, which is why they're excluded from the tile's range.
///
/// Only add-ons linked to this item are offered — the server rejects anything
/// else, so showing a tenant-wide list would build a picker whose choices get
/// refused.
Future<CartLine?> showItemOptionsSheet({
  required BuildContext context,
  required PosMenuItem item,
  required String currency,
}) {
  return showModalBottomSheet<CartLine>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ItemOptionsSheet(item: item, currency: currency),
  );
}

class _ItemOptionsSheet extends StatefulWidget {
  const _ItemOptionsSheet({required this.item, required this.currency});

  final PosMenuItem item;
  final String currency;

  @override
  State<_ItemOptionsSheet> createState() => _ItemOptionsSheetState();
}

class _ItemOptionsSheetState extends State<_ItemOptionsSheet> {
  PosVariant? _variant;
  final Set<String> _modifierIds = {};
  final _notes = TextEditingController();
  int _qty = 1;

  @override
  void initState() {
    super.initState();
    // Forced choice: a dish with variants has no orderable base price.
    if (widget.item.variants.isNotEmpty) _variant = widget.item.variants.first;
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  int get _unitCents =>
      widget.item.basePriceCents +
      (_variant?.priceDeltaCents ?? 0) +
      widget.item.modifiers
          .where((m) => _modifierIds.contains(m.id))
          .fold(0, (s, m) => s + m.priceCents);

  void _submit() {
    Navigator.of(context).pop(
      CartLine(
        localId: const Uuid().v4(),
        item: widget.item,
        qty: _qty,
        variant: _variant,
        modifiers: widget.item.modifiers
            .where((m) => _modifierIds.contains(m.id))
            .toList(),
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Column(
        children: [
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(Tokens.radiusMd),
                      child: SizedBox(
                        width: 64,
                        height: 64,
                        child: DishThumb(
                          name: item.name,
                          imageUrl: item.imageUrl,
                          monogramSize: 22,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (item.isVeg != null) ...[
                                VegMark(isVeg: item.isVeg),
                                const SizedBox(width: 6),
                              ],
                              Expanded(
                                child: Text(
                                  item.name,
                                  style: theme.textTheme.titleMedium,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            money(_unitCents, widget.currency),
                            style:
                                (theme.textTheme.bodyLarge ?? const TextStyle())
                                    .tabular,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                      tooltip: 'Close',
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                if (item.variants.isNotEmpty) ...[
                  Text('Select variant', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final v in item.variants)
                        AppChoiceChip(
                          label: v.name,
                          detail: money(
                            item.basePriceCents + v.priceDeltaCents,
                            widget.currency,
                          ),
                          selected: _variant?.id == v.id,
                          showCheck: true,
                          onSelect: () => setState(() => _variant = v),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],

                if (item.modifiers.isNotEmpty) ...[
                  Text('Add-ons', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final m in item.modifiers)
                        AppChoiceChip(
                          label: m.name,
                          detail: '+${money(m.priceCents, widget.currency)}',
                          selected: _modifierIds.contains(m.id),
                          showCheck: true,
                          onSelect: () => setState(() {
                            if (!_modifierIds.remove(m.id)) {
                              _modifierIds.add(m.id);
                            }
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],

                Text('Cooking request', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                TextField(
                  controller: _notes,
                  minLines: 2,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'e.g. no chilli, extra crispy',
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),

          // Quantity + confirm pinned above the keyboard.
          SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                8 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Row(
                children: [
                  _QtyStepper(
                    qty: _qty,
                    onChanged: (q) => setState(() => _qty = q),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _submit,
                      child: Text(
                        'Add · ${money(_unitCents * _qty, widget.currency)}',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Quantity stepper. Both buttons are 44px — this is hit mid-rush.
class _QtyStepper extends StatelessWidget {
  const _QtyStepper({required this.qty, required this.onChanged});

  final int qty;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outline, width: 1.5),
        borderRadius: BorderRadius.circular(Tokens.radiusMd),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: qty > 1 ? () => onChanged(qty - 1) : null,
            icon: const Icon(Icons.remove),
            tooltip: 'One fewer',
            constraints: const BoxConstraints(
              minWidth: Tokens.tapTarget,
              minHeight: Tokens.tapTarget,
            ),
          ),
          SizedBox(
            width: 28,
            child: Text(
              '$qty',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontVariations: const [FontVariation('wght', 700)],
                fontFeatures: tabularFigures,
                fontSize: 16,
              ),
            ),
          ),
          IconButton(
            onPressed: qty < 99 ? () => onChanged(qty + 1) : null,
            icon: const Icon(Icons.add),
            tooltip: 'One more',
            constraints: const BoxConstraints(
              minWidth: Tokens.tapTarget,
              minHeight: Tokens.tapTarget,
            ),
          ),
        ],
      ),
    );
  }
}
