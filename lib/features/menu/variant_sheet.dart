import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format/money.dart';
import '../../core/theme/tokens.dart';
import '../../data/supabase/menu_repository.dart';

/// A size and what it does to the price, as typed by whoever is editing.
class VariantDraft {
  const VariantDraft({required this.name, required this.priceDeltaCents});

  final String name;
  final int priceDeltaCents;
}

/// Add or edit one size.
///
/// The sheet **owns its controllers** and disposes them in its own `State`.
/// Creating a `TextEditingController` beside a `showModalBottomSheet` and
/// disposing it after the await takes the app down on
/// `'_dependents.isEmpty': is not true` — the future resolves a frame before the
/// field unmounts. Learned once in Milestone E; not rediscovered here.
Future<VariantDraft?> showVariantSheet(
  BuildContext context, {
  required String itemName,
  required int basePriceCents,
  required String currency,
  MenuEditVariant? editing,
}) => showModalBottomSheet<VariantDraft>(
  context: context,
  isScrollControlled: true,
  builder: (_) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
    child: _VariantSheet(
      itemName: itemName,
      basePriceCents: basePriceCents,
      currency: currency,
      editing: editing,
    ),
  ),
);

class _VariantSheet extends StatefulWidget {
  const _VariantSheet({
    required this.itemName,
    required this.basePriceCents,
    required this.currency,
    this.editing,
  });

  final String itemName;
  final int basePriceCents;
  final String currency;
  final MenuEditVariant? editing;

  @override
  State<_VariantSheet> createState() => _VariantSheetState();
}

class _VariantSheetState extends State<_VariantSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.editing?.name ?? '',
  );
  late final TextEditingController _delta = TextEditingController(
    text: widget.editing == null
        ? ''
        : (widget.editing!.priceDeltaCents / 100).toStringAsFixed(2),
  );

  /// A Half is cheaper than the base dish, so "less" has to be a tap rather
  /// than a minus sign someone remembers to type on a phone keyboard.
  late bool _isLess = (widget.editing?.priceDeltaCents ?? 0) < 0;

  @override
  void initState() {
    super.initState();
    _name.addListener(_onChanged);
    _delta.addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _name.dispose();
    _delta.dispose();
    super.dispose();
  }

  int? get _deltaCents {
    final raw = _delta.text.trim();
    if (raw.isEmpty) return 0;
    final n = double.tryParse(raw);
    if (n == null) return null;
    final cents = (n.abs() * 100).round();
    return _isLess ? -cents : cents;
  }

  bool get _valid => _name.text.trim().isNotEmpty && _deltaCents != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cents = _deltaCents;
    final sells = cents == null ? null : widget.basePriceCents + cents;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.editing == null ? 'Add a size' : 'Edit size',
              style: theme.textTheme.titleMedium,
            ),
            Text(
              widget.itemName,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              autofocus: widget.editing == null,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'Half, 1 kg, Large',
                constraints: BoxConstraints(minHeight: Tokens.tapTarget),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _delta,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    decoration: InputDecoration(
                      labelText: 'Price change',
                      prefixText: _isLess ? '− ' : '+ ',
                      hintText: '0.00',
                      constraints: const BoxConstraints(
                        minHeight: Tokens.tapTarget,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Sign as a segmented control, not a typed minus: colour alone
                // would carry the meaning otherwise, and +/− survives a
                // greyscale screen.
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('More')),
                    ButtonSegment(value: true, label: Text('Less')),
                  ],
                  selected: {_isLess},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() => _isLess = s.first),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              sells == null
                  ? 'Enter a number for the price change.'
                  : 'Sells for ${money(sells, widget.currency)}',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _valid
                    ? () => Navigator.of(context).pop(
                        VariantDraft(
                          name: _name.text.trim(),
                          priceDeltaCents: _deltaCents ?? 0,
                        ),
                      )
                    : null,
                child: Text(widget.editing == null ? 'Add size' : 'Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
