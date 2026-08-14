import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../core/format/money.dart';
import '../../core/theme/tokens.dart';
import 'models.dart';

/// The clamp `place_staff_order` and `amend_order_add_custom_item` both apply.
const _maxCustomPriceMajor = 100000;

/// An off-menu line — a plating charge, a special the kitchen ran today.
///
/// **The one place in this app where a price is typed rather than looked up.**
/// It is checked here for the waiter's sake and again on the server for
/// everyone else's; the line carries no `item_id`, so it can never stand in for
/// a menu item's price, and it deducts no stock.
///
/// Ported from the web's `components/pos/custom-item-dialog.tsx` so the two
/// clients accept the same thing.
Future<CartLine?> showCustomItemSheet({
  required BuildContext context,
  required String currency,
}) {
  return showModalBottomSheet<CartLine>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _CustomItemSheet(currency: currency),
  );
}

class _CustomItemSheet extends StatefulWidget {
  const _CustomItemSheet({required this.currency});

  final String currency;

  @override
  State<_CustomItemSheet> createState() => _CustomItemSheetState();
}

class _CustomItemSheetState extends State<_CustomItemSheet> {
  // The sheet owns its controllers — see the note on `showVoidReasonDialog`.
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _notes = TextEditingController();

  int _qty = 1;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _notes.dispose();
    super.dispose();
  }

  int? get _priceCents {
    final major = double.tryParse(_price.text.trim());
    if (major == null || major < 0 || major > _maxCustomPriceMajor) return null;
    return (major * 100).round();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      return setState(() => _error = 'Give the item a name.');
    }
    final cents = _priceCents;
    if (cents == null) {
      return setState(
        () => _error =
            'That price looks wrong. Enter an amount between 0 and '
            '$_maxCustomPriceMajor.',
      );
    }
    final notes = _notes.text.trim();
    Navigator.of(context).pop(
      CartLine(
        localId: const Uuid().v4(),
        item: PosMenuItem.custom(name: name, priceCents: cents),
        qty: _qty,
        notes: notes.isEmpty ? null : notes,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cents = _priceCents;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Something off the menu', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'It goes to the kitchen on the expo ticket and onto the bill. No '
              'stock comes off for it.',
              style: theme.textTheme.bodySmall,
            ),

            const SizedBox(height: 16),
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 60,
              onChanged: (_) => setState(() => _error = null),
              decoration: const InputDecoration(
                labelText: 'What is it',
                hintText: 'e.g. Birthday cake plating',
              ),
            ),
            TextField(
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              onChanged: (_) => setState(() => _error = null),
              decoration: InputDecoration(
                labelText: 'Price each',
                prefixText: '${widget.currency} ',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _notes,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Note for the kitchen (optional)',
                isDense: true,
              ),
            ),

            const SizedBox(height: 16),
            Row(
              children: [
                Text('Quantity', style: theme.textTheme.labelMedium),
                const Spacer(),
                IconButton(
                  onPressed: _qty <= 1 ? null : () => setState(() => _qty -= 1),
                  icon: const Icon(Icons.remove_circle_outline),
                  iconSize: 28,
                ),
                SizedBox(
                  width: 44,
                  child: Text(
                    '$_qty',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  onPressed: _qty >= 99
                      ? null
                      : () => setState(() => _qty += 1),
                  icon: const Icon(Icons.add_circle_outline),
                  iconSize: 28,
                ),
              ],
            ),

            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],

            const SizedBox(height: 12),
            FilledButton(
              onPressed: _submit,
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, Tokens.tapTarget),
              ),
              child: Text(
                cents == null
                    ? 'Add to the order'
                    : 'Add ${money(cents * _qty, widget.currency)}',
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}
