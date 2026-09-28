import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/supabase/day_report_repository.dart';

/// What was counted at night.
class DayCountDraft {
  const DayCountDraft({required this.cashCents, this.onlineCents, this.note});

  final int cashCents;
  final int? onlineCents;
  final String? note;
}

/// The paper book's last line — cash in hand, online received — typed in.
/// Owns its controllers and disposes them in its own `State`.
Future<DayCountDraft?> showDayCountSheet(
  BuildContext context, {
  required DayCashBook book,
  required String currency,
}) => showModalBottomSheet<DayCountDraft>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (sheetContext) => Padding(
    padding: EdgeInsets.only(
      bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
    ),
    child: _DayCountSheet(book: book, currency: currency),
  ),
);

class _DayCountSheet extends StatefulWidget {
  const _DayCountSheet({required this.book, required this.currency});

  final DayCashBook book;
  final String currency;

  @override
  State<_DayCountSheet> createState() => _DayCountSheetState();
}

class _DayCountSheetState extends State<_DayCountSheet> {
  late final TextEditingController _cash;
  late final TextEditingController _online;
  late final TextEditingController _note;
  String? _error;

  static String _plain(int? cents) => cents == null
      ? ''
      : cents % 100 == 0
      ? (cents ~/ 100).toString()
      : (cents / 100).toStringAsFixed(2);

  static int? _cents(String raw) {
    final v = double.tryParse(raw.trim());
    return v == null ? null : (v * 100).round();
  }

  @override
  void initState() {
    super.initState();
    _cash = TextEditingController(text: _plain(widget.book.countedCashCents));
    _online = TextEditingController(
      text: _plain(widget.book.countedOnlineCents),
    );
    _note = TextEditingController(text: widget.book.note ?? '');
  }

  @override
  void dispose() {
    _cash.dispose();
    _online.dispose();
    _note.dispose();
    super.dispose();
  }

  void _submit() {
    final cash = _cents(_cash.text);
    final onlineRaw = _online.text.trim();
    final online = onlineRaw.isEmpty ? null : _cents(onlineRaw);
    if (cash == null || cash < 0) {
      setState(() => _error = 'Enter the cash in hand — 0 if there is none.');
      return;
    }
    if (onlineRaw.isNotEmpty && (online == null || online < 0)) {
      setState(() => _error = 'Online received must be zero or more.');
      return;
    }
    Navigator.of(context).pop(
      DayCountDraft(cashCents: cash, onlineCents: online, note: _note.text),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    InputDecoration money(String label, {String? hint}) => InputDecoration(
      labelText: '$label (${widget.currency})',
      hintText: hint,
      border: const OutlineInputBorder(),
    );
    final numeric = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))];
    const keyboard = TextInputType.numberWithOptions(decimal: true);
    final big = theme.textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w700,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.book.closed ? 'Recount the day' : 'Close the day',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Count the cash in hand and check online received.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _cash,
              autofocus: true,
              keyboardType: keyboard,
              inputFormatters: numeric,
              style: big,
              decoration: money('Cash in hand'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _online,
              keyboardType: keyboard,
              inputFormatters: numeric,
              style: big,
              decoration: money('Online received', hint: 'Optional'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              maxLength: 280,
              decoration: const InputDecoration(
                labelText: 'Note',
                hintText: 'Rs 500 handed to owner',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            FilledButton.icon(
              onPressed: _submit,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              icon: const Icon(Icons.check_circle_outline),
              label: Text(
                widget.book.closed ? 'Save recount' : 'Close the day',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
