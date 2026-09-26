import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/widgets/choice_chip.dart';
import '../../core/widgets/photo_picker.dart';
import '../../data/supabase/expenses_repository.dart';

/// An expense as typed, before it is saved.
class ExpenseDraft {
  const ExpenseDraft({
    required this.categoryId,
    required this.amountCents,
    required this.note,
    required this.paidFrom,
    this.photo,
  });

  final String categoryId;
  final int amountCents;
  final String note;
  final PaidFrom paidFrom;

  /// Only offered when adding; an existing expense's photo is managed from
  /// its own menu.
  final PickedPhoto? photo;
}

/// Add or edit one expense: amount, tap a category, a few words, where the
/// money came from. Chips, not dropdowns — this is two taps and a word for
/// someone standing at the back door paying a rickshaw.
///
/// Owns its controllers and disposes them in its own `State`.
Future<ExpenseDraft?> showExpenseSheet(
  BuildContext context, {
  required List<ExpenseCategory> categories,
  required String currency,
  Expense? editing,
}) => showModalBottomSheet<ExpenseDraft>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (sheetContext) => Padding(
    padding: EdgeInsets.only(
      bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
    ),
    child: _ExpenseSheet(
      categories: categories,
      currency: currency,
      editing: editing,
    ),
  ),
);

class _ExpenseSheet extends StatefulWidget {
  const _ExpenseSheet({
    required this.categories,
    required this.currency,
    this.editing,
  });

  final List<ExpenseCategory> categories;
  final String currency;
  final Expense? editing;

  @override
  State<_ExpenseSheet> createState() => _ExpenseSheetState();
}

class _ExpenseSheetState extends State<_ExpenseSheet> {
  late final TextEditingController _amount;
  late final TextEditingController _note;
  String? _category;
  late PaidFrom _paidFrom;
  PickedPhoto? _photo;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    _amount = TextEditingController(
      text: e == null ? '' : _plain(e.amountCents),
    );
    _note = TextEditingController(text: e?.note ?? '');
    _category =
        e?.categoryId ??
        (widget.categories.isEmpty ? null : widget.categories.first.id);
    _paidFrom = e?.paidFrom ?? PaidFrom.cash;
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  static String _plain(int cents) => cents % 100 == 0
      ? (cents ~/ 100).toString()
      : (cents / 100).toStringAsFixed(2);

  /// Cents from what was typed. Rounded, never floored: 0.29 × 100 is
  /// 28.999… in binary, and flooring it would lose a paisa.
  static int? _cents(String raw) {
    final v = double.tryParse(raw.trim());
    if (v == null) return null;
    return (v * 100).round();
  }

  void _submit() {
    final cents = _cents(_amount.text);
    final note = _note.text.trim();
    String? error;
    if (cents == null || cents <= 0) {
      error = 'Enter an amount above zero.';
    } else if (_category == null) {
      error = 'Pick a category.';
    } else if (note.isEmpty) {
      error = 'Say what it was for — “rice”, “ride for dishwasher”.';
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(
      ExpenseDraft(
        categoryId: _category!,
        amountCents: cents!,
        note: note,
        paidFrom: _paidFrom,
        photo: _photo,
      ),
    );
  }

  Future<void> _pickPhoto() async {
    final photo = await pickPhoto(context);
    if (photo != null && mounted) setState(() => _photo = photo);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // An archived category stays selectable on the row that already uses it.
    final editing = widget.editing;
    final options = [
      ...widget.categories,
      if (editing != null &&
          !widget.categories.any((c) => c.id == editing.categoryId))
        ExpenseCategory(
          id: editing.categoryId,
          name: editing.category,
          archived: true,
        ),
    ];

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              editing == null ? 'Log an expense' : 'Edit expense',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amount,
              autofocus: editing == null,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              decoration: InputDecoration(
                labelText: 'Amount (${widget.currency})',
                hintText: '100',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Text('Category', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in options)
                  AppChoiceChip(
                    label: c.name,
                    selected: _category == c.id,
                    showCheck: true,
                    onSelect: () => setState(() => _category = c.id),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _note,
              maxLength: 280,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'What was it for?',
                hintText: 'Rice 5kg · Pathao for dishwasher',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text('Paid from', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in PaidFrom.values)
                  AppChoiceChip(
                    label: p.label,
                    detail: p.hint,
                    selected: _paidFrom == p,
                    showCheck: true,
                    onSelect: () => setState(() => _paidFrom = p),
                  ),
              ],
            ),
            if (editing == null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: _pickPhoto,
                icon: Icon(
                  _photo == null
                      ? Icons.add_a_photo_outlined
                      : Icons.check_circle_outline,
                ),
                label: Text(
                  _photo == null
                      ? 'Add receipt photo (optional)'
                      : 'Receipt photo added — tap to change',
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _submit,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              icon: Icon(editing == null ? Icons.add : Icons.check),
              label: Text(editing == null ? 'Add expense' : 'Save changes'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ask why an expense is being voided. Owns its controller.
Future<String?> showVoidExpenseDialog(
  BuildContext context, {
  required String title,
}) => showDialog<String>(
  context: context,
  builder: (_) => _VoidDialog(title: title),
);

class _VoidDialog extends StatefulWidget {
  const _VoidDialog({required this.title});

  final String title;

  @override
  State<_VoidDialog> createState() => _VoidDialogState();
}

class _VoidDialogState extends State<_VoidDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "It stops counting toward the day's expenses and expected cash. "
            'The entry stays visible, struck through, with your reason.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reason,
            autofocus: true,
            maxLength: 280,
            decoration: const InputDecoration(
              labelText: 'Reason',
              hintText: 'Entered twice',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Keep it'),
        ),
        FilledButton.tonal(
          onPressed: _reason.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(_reason.text.trim()),
          child: const Text('Void expense'),
        ),
      ],
    );
  }
}
