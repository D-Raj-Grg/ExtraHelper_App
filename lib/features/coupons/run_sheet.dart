import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/choice_chip.dart';
import '../../data/supabase/coupon_batches_repository.dart';
import 'coupon_sheet.dart' show CouponDateButton;
import 'coupon_status.dart';

/// Make a flyer run: how many codes, what they take off, when they work.
/// Returns the draft to create, or null. Owns its controllers (see the
/// dialog trap in CLAUDE.md).
Future<RunDraft?> showNewRunSheet(
  BuildContext context, {
  required String currency,
}) => showModalBottomSheet<RunDraft>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
    child: _RunSheet(currency: currency),
  ),
);

/// Rename a run or move its dates; the codes and the deal are on paper.
Future<RunEdit?> showEditRunSheet(
  BuildContext context, {
  required CouponBatch batch,
}) => showModalBottomSheet<RunEdit>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
    child: _RunSheet(currency: '', editing: batch),
  ),
);

class _RunSheet extends StatefulWidget {
  const _RunSheet({required this.currency, this.editing});

  final String currency;
  final CouponBatch? editing;

  @override
  State<_RunSheet> createState() => _RunSheetState();
}

class _RunSheetState extends State<_RunSheet> {
  late final TextEditingController _name;
  late final TextEditingController _count;
  late final TextEditingController _prefix;
  late final TextEditingController _value;
  String _type = 'percent';
  bool _dineInOnly = false;
  DateTime? _from;
  DateTime? _through;
  bool _fromTouched = false;
  bool _throughTouched = false;
  String? _error;

  CouponBatch? get _editing => widget.editing;

  @override
  void initState() {
    super.initState();
    final e = _editing;
    _name = TextEditingController(text: e?.name ?? '');
    _count = TextEditingController(text: '100');
    _prefix = TextEditingController();
    _value = TextEditingController(text: '10');
    _from = e?.validFrom?.toLocal();
    _through = e?.validTo == null ? null : lastDayOf(e!.validTo!);
  }

  @override
  void dispose() {
    _name.dispose();
    _count.dispose();
    _prefix.dispose();
    _value.dispose();
    super.dispose();
  }

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  Future<void> _pickDate({required bool start}) async {
    final now = DateTime.now();
    final initial = _day((start ? _from : _through) ?? now);
    var first = DateTime(now.year - 1);
    var last = DateTime(now.year + 5);
    if (initial.isBefore(first)) first = initial;
    if (initial.isAfter(last)) last = initial;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      helpText: start ? 'Valid from' : 'Valid through',
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (start) {
        _from = _day(picked);
        _fromTouched = true;
      } else {
        _through = _day(picked);
        _throughTouched = true;
      }
      _error = null;
    });
  }

  void _clearDate({required bool start}) => setState(() {
    if (start) {
      _from = null;
      _fromTouched = true;
    } else {
      _through = null;
      _throughTouched = true;
    }
  });

  void _submit() {
    final e = _editing;
    // Untouched dates go back exactly as stored (tenant zone, not the phone's).
    final from = e == null || _fromTouched ? _from : e.validFrom;
    final to = e == null || _throughTouched
        ? (_through == null ? null : exclusiveEndOf(_through!))
        : e.validTo;
    if (e != null) {
      final edit = RunEdit(name: _name.text, validFrom: from, validTo: to);
      final problem = edit.validate();
      if (problem != null) {
        setState(() => _error = problem);
        return;
      }
      Navigator.of(context).pop(edit);
      return;
    }
    final count = int.tryParse(_count.text.trim());
    if (count == null) {
      setState(() => _error = 'How many codes? A whole number.');
      return;
    }
    final value = double.tryParse(_value.text.trim());
    if (value == null) {
      setState(() => _error = 'Enter the discount as a number.');
      return;
    }
    final draft = RunDraft(
      name: _name.text,
      count: count,
      prefix: _prefix.text,
      type: _type,
      value: value,
      validFrom: from,
      validTo: to,
      dineInOnly: _dineInOnly,
    );
    final problem = draft.validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    Navigator.of(context).pop(draft);
  }

  void _clearError([String? _]) {
    if (_error != null) setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = _editing;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              e == null ? 'New flyer run' : 'Edit run',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Run name',
                hintText: 'Dashain flyers',
                border: OutlineInputBorder(),
              ),
              onChanged: _clearError,
            ),
            if (e == null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _count,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Codes',
                        helperText: '1 to 1000',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: _clearError,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _prefix,
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[A-Za-z0-9]'),
                        ),
                        LengthLimitingTextInputFormatter(8),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Prefix',
                        hintText: 'DASHAIN',
                        helperText: '2 to 8 letters or digits',
                        border: OutlineInputBorder(),
                      ),
                      style: const TextStyle(fontFamily: 'monospace'),
                      onChanged: _clearError,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Discount', style: theme.textTheme.labelMedium),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: AppChoiceChip(
                      label: 'Percent off',
                      selected: _type == 'percent',
                      showCheck: true,
                      onSelect: () => setState(() {
                        _type = 'percent';
                        _error = null;
                      }),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AppChoiceChip(
                      label: '${widget.currency} off',
                      selected: _type == 'flat',
                      showCheck: true,
                      onSelect: () => setState(() {
                        _type = 'flat';
                        _error = null;
                      }),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _value,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                decoration: InputDecoration(
                  labelText: _type == 'percent' ? 'Percent' : 'Amount',
                  suffixText: _type == 'percent' ? '%' : widget.currency,
                  border: const OutlineInputBorder(),
                ),
                onChanged: _clearError,
              ),
            ] else ...[
              const SizedBox(height: 8),
              Text(
                'Codes, prefix and discount are printed, so they stay. '
                'Changing the dates moves every code in the run.',
                style: muted,
              ),
            ],
            const SizedBox(height: 16),
            Text('Valid', style: theme.textTheme.labelMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: CouponDateButton(
                    label: 'From',
                    value: _from,
                    onTap: () => _pickDate(start: true),
                    onClear: _from == null
                        ? null
                        : () => _clearDate(start: true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: CouponDateButton(
                    label: 'Through',
                    value: _through,
                    onTap: () => _pickDate(start: false),
                    onClear: _through == null
                        ? null
                        : () => _clearDate(start: false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('Blank means no start or no end.', style: muted),
            if (e == null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _dineInOnly,
                onChanged: (v) => setState(() => _dineInOnly = v),
                title: const Text('Dine in only'),
                subtitle: const Text('Off means any order type.'),
              ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: Tokens.tapTarget + 4,
              child: FilledButton(
                onPressed: _submit,
                child: Text(e == null ? 'Make codes' : 'Save run'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
