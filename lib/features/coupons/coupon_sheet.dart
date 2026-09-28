import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format/labels.dart';
import '../../core/format/when.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/choice_chip.dart';
import '../../data/supabase/coupons_repository.dart';
import 'coupon_status.dart';

/// Create or edit one coupon. Returns the draft to save, or null.
///
/// Owns its controllers and disposes them in its own `State` — creating them
/// beside `showModalBottomSheet` and disposing after the await takes the app
/// down on `'_dependents.isEmpty': is not true`.
///
/// Dates are picked as calendar days in the phone's timezone. "Valid through
/// 30 Sep" means the whole of the 30th, so the stored end is the start of the
/// 1st — the same exclusive bound the web computes, in the tenant's zone.
/// The phone has no tz database; staff phones are on the restaurant's clock.
Future<CouponDraft?> showCouponSheet(
  BuildContext context, {
  required String currency,
  Coupon? editing,
}) => showModalBottomSheet<CouponDraft>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
    child: _CouponSheet(currency: currency, editing: editing),
  ),
);

class _CouponSheet extends StatefulWidget {
  const _CouponSheet({required this.currency, this.editing});

  final String currency;
  final Coupon? editing;

  @override
  State<_CouponSheet> createState() => _CouponSheetState();
}

class _CouponSheetState extends State<_CouponSheet> {
  late final TextEditingController _code;
  late final TextEditingController _name;
  late final TextEditingController _value;
  late final TextEditingController _limit;
  late final TextEditingController _min;
  late String _type;
  late bool _active;
  late bool _oncePerCustomer;
  late Set<String> _orderTypes;
  DateTime? _from;

  /// The last *inclusive* day, as picked. Converted to the exclusive bound
  /// on submit.
  DateTime? _through;

  String? _error;

  Coupon? get _editing => widget.editing;

  @override
  void initState() {
    super.initState();
    final e = _editing;
    _code = TextEditingController(text: e?.code ?? '');
    _name = TextEditingController(text: e?.name ?? '');
    _value = TextEditingController(text: e == null ? '10' : trimZeros(e.value));
    _limit = TextEditingController(text: e?.usageLimit?.toString() ?? '');
    _min = TextEditingController(
      text: e == null || e.minSubtotalCents == 0
          ? ''
          : trimZeros(e.minSubtotalCents / 100),
    );
    _type = e?.type ?? 'percent';
    _active = e?.isActive ?? true;
    _oncePerCustomer = e?.oncePerCustomer ?? false;
    _orderTypes = {...?e?.orderTypes};
    _from = e?.validFrom?.toLocal();
    final to = e?.validTo?.toLocal();
    // Stored exclusive start-of-next-day → the inclusive day shown.
    _through = to == null ? null : _day(to.subtract(const Duration(days: 1)));
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _value.dispose();
    _limit.dispose();
    _min.dispose();
    super.dispose();
  }

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  Future<void> _pickDate({required bool start}) async {
    final now = DateTime.now();
    final initial = (start ? _from : _through) ?? _day(now);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      helpText: start ? 'Valid from' : 'Valid through',
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (start) {
        _from = _day(picked);
      } else {
        _through = _day(picked);
      }
      _error = null;
    });
  }

  static int? _cents(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return 0;
    final n = double.tryParse(t);
    if (n == null) return null;
    return (n * 100).round();
  }

  void _submit() {
    final value = double.tryParse(_value.text.trim());
    if (value == null) {
      setState(() => _error = 'Enter the discount as a number.');
      return;
    }
    final limitText = _limit.text.trim();
    final limit = limitText.isEmpty ? null : int.tryParse(limitText);
    if (limitText.isNotEmpty && limit == null) {
      setState(() => _error = 'The usage limit is a whole number.');
      return;
    }
    final minCents = _cents(_min.text);
    if (minCents == null) {
      setState(() => _error = 'Enter the minimum order as an amount.');
      return;
    }
    final draft = CouponDraft(
      id: _editing?.id,
      code: _code.text,
      name: _name.text,
      type: _type,
      value: value,
      isActive: _active,
      validFrom: _from,
      validTo: _through?.add(const Duration(days: 1)),
      usageLimit: limit,
      minSubtotalCents: minCents,
      oncePerCustomer: _oncePerCustomer,
      orderTypes: _orderTypes.toList(),
    );
    final problem = draft.validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    Navigator.of(context).pop(draft);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = _editing;
    final codeLocked = e?.codeLocked ?? false;
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
              e == null ? 'New coupon' : 'Edit coupon',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _code,
              readOnly: codeLocked,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9-]')),
              ],
              decoration: InputDecoration(
                labelText: 'Code',
                hintText: 'Leave blank to make one',
                helperText: codeLocked
                    ? 'Used on a bill, so the code stays.'
                    : 'Letters, numbers and dashes. Blank = SAVE10-XXXX.',
                border: const OutlineInputBorder(),
              ),
              style: const TextStyle(fontFamily: 'monospace'),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Campaign',
                hintText: 'Dashain flyer, Opening week',
                border: OutlineInputBorder(),
              ),
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
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            const SizedBox(height: 16),
            Text('Valid', style: theme.textTheme.labelMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _DateButton(
                    label: 'From',
                    value: _from,
                    onTap: () => _pickDate(start: true),
                    onClear: _from == null
                        ? null
                        : () => setState(() => _from = null),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _DateButton(
                    label: 'Through',
                    value: _through,
                    onTap: () => _pickDate(start: false),
                    onClear: _through == null
                        ? null
                        : () => setState(() => _through = null),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('Blank means no start or no end.', style: muted),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _limit,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: 'Usage limit',
                      hintText: 'No limit',
                      helperText: e == null
                          ? null
                          : 'Used ${e.usedCount} so far',
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) {
                      if (_error != null) setState(() => _error = null);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _min,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    decoration: InputDecoration(
                      labelText: 'Minimum order',
                      hintText: 'None',
                      suffixText: widget.currency,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) {
                      if (_error != null) setState(() => _error = null);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Order type', style: theme.textTheme.labelMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in couponOrderTypes)
                  AppChoiceChip(
                    label: orderTypeLabel(t),
                    selected: _orderTypes.contains(t),
                    showCheck: true,
                    onSelect: () => setState(() {
                      if (!_orderTypes.remove(t)) _orderTypes.add(t);
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'None ticked means any order. A QR table counts as dine in.',
              style: muted,
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _oncePerCustomer,
              onChanged: (v) => setState(() => _oncePerCustomer = v),
              title: const Text('Once per customer'),
              subtitle: const Text('A guest on the bill can use it one time.'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _active,
              onChanged: (v) => setState(() => _active = v),
              title: const Text('Active'),
              subtitle: Text(
                _active
                    ? 'Codes work as soon as the dates allow.'
                    : 'Paused — nobody can use it until you resume.',
              ),
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
                child: Text(e == null ? 'Create coupon' : 'Save coupon'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateButton extends StatelessWidget {
  const _DateButton({
    required this.label,
    required this.value,
    required this.onTap,
    this.onClear,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final v = value;
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, Tokens.tapTarget + 4),
        alignment: Alignment.centerLeft,
      ),
      icon: const Icon(Icons.calendar_today_outlined, size: 18),
      label: Row(
        children: [
          Expanded(
            child: Text(
              v == null ? label : '$label ${billDate(v)}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onClear != null)
            InkWell(
              onTap: onClear,
              customBorder: const CircleBorder(),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close, size: 16),
              ),
            ),
        ],
      ),
    );
  }
}
