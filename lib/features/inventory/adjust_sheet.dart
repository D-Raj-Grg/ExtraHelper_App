import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/supabase/inventory_repository.dart';
import 'quantity.dart';

/// What the store keeper decided: how much moved, why, and the note that
/// justifies it.
class StockAdjustment {
  const StockAdjustment({
    required this.delta,
    required this.type,
    required this.reason,
  });

  final double delta;
  final StockMovementType type;
  final String reason;
}

/// Move stock by a delta.
///
/// The dialog **owns its controllers** and disposes them in its own `State`.
/// Creating a `TextEditingController` beside a `showModalBottomSheet` and
/// disposing it after the await takes the whole app down on
/// `'_dependents.isEmpty': is not true` — the future resolves a frame before the
/// field unmounts. That cost a Milestone E crash; it is not rediscovered here.
Future<StockAdjustment?> showAdjustSheet(
  BuildContext context,
  InventoryItem item,
) => showModalBottomSheet<StockAdjustment>(
  context: context,
  isScrollControlled: true,
  builder: (_) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
    child: _AdjustSheet(item: item),
  ),
);

class _AdjustSheet extends StatefulWidget {
  const _AdjustSheet({required this.item});

  final InventoryItem item;

  @override
  State<_AdjustSheet> createState() => _AdjustSheetState();
}

class _AdjustSheetState extends State<_AdjustSheet> {
  final _amount = TextEditingController();
  final _reason = TextEditingController();

  StockMovementType _type = StockMovementType.purchase;

  /// Out is the common case for wastage and staff meals, in for a delivery.
  /// Held separately from the amount so the sign is a deliberate tap, not a
  /// minus someone has to remember to type.
  bool _isOut = false;

  @override
  void initState() {
    super.initState();
    _amount.addListener(_onChanged);
    _reason.addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  double get _magnitude => double.tryParse(_amount.text.trim()) ?? 0;

  double get _delta => _isOut ? -_magnitude : _magnitude;

  bool get _canSave =>
      _magnitude > 0 && (!_type.needsReason || _reason.text.trim().isNotEmpty);

  void _selectType(StockMovementType t) => setState(() {
    _type = t;
    // Wastage, staff meals and transfers only ever go out; a delivery only ever
    // comes in. A correction can go either way, so it leaves the choice alone.
    _isOut = switch (t) {
      StockMovementType.purchase => false,
      StockMovementType.wastage ||
      StockMovementType.staffMeal ||
      StockMovementType.transfer => true,
      StockMovementType.adjustment => _isOut,
    };
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final item = widget.item;
    final resulting = item.currentQty + _delta;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.name, style: theme.textTheme.titleMedium),
            const SizedBox(height: 2),
            Text(
              'On hand ${qtyWithUom(item.currentQty, item.uom)}',
              style: theme.textTheme.bodySmall?.tabular,
            ),
            const SizedBox(height: 16),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in StockMovementType.values)
                  ChoiceChip(
                    label: Text(t.label),
                    selected: _type == t,
                    // Selection carries a check, not just a fill — this must
                    // survive a greyscale screenshot.
                    avatar: _type == t
                        ? const Icon(Icons.check, size: 16)
                        : null,
                    onSelected: (_) => _selectType(t),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Direction as words, never a bare sign: "Out" is unambiguous
                // at arm's length in a cold room.
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: false,
                      label: Text('In'),
                      icon: Icon(Icons.add),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text('Out'),
                      icon: Icon(Icons.remove),
                    ),
                  ],
                  selected: {_isOut},
                  onSelectionChanged: (s) => setState(() => _isOut = s.first),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _amount,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    textAlign: TextAlign.right,
                    style: theme.textTheme.headlineSmall?.tabular,
                    decoration: InputDecoration(
                      labelText: 'Amount',
                      suffixText: item.uom,
                      constraints: const BoxConstraints(
                        minHeight: Tokens.tapTarget,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            if (_type.needsReason) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _reason,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'What happened?',
                  hintText: 'Spoiled in the walk-in',
                  helperText:
                      'Required — a write-off is audited with your name.',
                ),
              ),
            ],

            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(Tokens.radiusMd),
              ),
              child: Row(
                children: [
                  Icon(
                    _isOut ? Icons.trending_down : Icons.trending_up,
                    size: 18,
                    color: _isOut ? semantic.attentionText : semantic.goodText,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _magnitude == 0
                          ? 'Enter an amount'
                          : '${signedQty(_delta, item.uom)}  ·  leaves '
                                '${qtyWithUom(resulting, item.uom)}',
                      style: theme.textTheme.bodyMedium?.tabular,
                    ),
                  ),
                ],
              ),
            ),
            // Only once there is a movement to judge. On an item already below
            // zero this warned before anything had been typed, which reads as
            // an objection to opening the sheet at all.
            if (_magnitude > 0 && resulting < 0) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.warning_amber_outlined,
                    size: 16,
                    color: semantic.attentionText,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'That takes this below zero. Count it instead if the '
                      'shelf is simply empty.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _canSave
                        ? () => Navigator.of(context).pop(
                            StockAdjustment(
                              delta: _delta,
                              type: _type,
                              reason: _reason.text.trim(),
                            ),
                          )
                        : null,
                    child: const Text('Save movement'),
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
