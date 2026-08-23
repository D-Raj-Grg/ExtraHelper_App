import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../data/supabase/settings_repository.dart';
import 'charges_form.dart';

/// Add or edit one tax rule.
///
/// The sheet **owns its controllers** and disposes them in its own `State` —
/// creating them beside `showModalBottomSheet` and disposing after the await
/// takes the app down on `'_dependents.isEmpty': is not true`, because the
/// future resolves a frame before the field unmounts.
Future<TaxRule?> showTaxRuleSheet(
  BuildContext context, {
  TaxRule? editing,
}) => showModalBottomSheet<TaxRule>(
  context: context,
  isScrollControlled: true,
  builder: (_) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
    child: _TaxRuleSheet(editing: editing),
  ),
);

class _TaxRuleSheet extends StatefulWidget {
  const _TaxRuleSheet({this.editing});

  final TaxRule? editing;

  @override
  State<_TaxRuleSheet> createState() => _TaxRuleSheetState();
}

class _TaxRuleSheetState extends State<_TaxRuleSheet> {
  late final TextEditingController _name;
  late final TextEditingController _rate;
  late bool _inclusive;

  String? _nameError;
  String? _rateError;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.editing?.name ?? '');
    _rate = TextEditingController(
      text: widget.editing == null ? '' : formatRate(widget.editing!.rate),
    );
    _inclusive = widget.editing?.inclusive ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _rate.dispose();
    super.dispose();
  }

  void _submit() {
    final nameError = validateTaxRuleName(_name.text);
    final rateError = validateTaxRuleRate(_rate.text);
    if (nameError != null || rateError != null) {
      setState(() {
        _nameError = nameError;
        _rateError = rateError;
      });
      return;
    }
    Navigator.of(context).pop(
      TaxRule(
        name: _name.text.trim(),
        rate: double.parse(_rate.text.trim()),
        inclusive: _inclusive,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.editing == null ? 'Add a tax rule' : 'Edit tax rule',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              autofocus: widget.editing == null,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'Name',
                hintText: 'VAT, GST, service tax',
                border: const OutlineInputBorder(),
                errorText: _nameError,
              ),
              onChanged: (_) {
                if (_nameError != null) setState(() => _nameError = null);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _rate,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Rate',
                suffixText: '%',
                border: const OutlineInputBorder(),
                errorText: _rateError,
              ),
              onChanged: (_) {
                if (_rateError != null) setState(() => _rateError = null);
              },
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _inclusive,
              onChanged: (value) => setState(() => _inclusive = value),
              title: const Text('Already in the price'),
              subtitle: Text(
                _inclusive
                    ? 'Inclusive — the menu price already contains this.'
                    : 'Exclusive — added on top of the subtotal and service '
                          'charge.',
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: Tokens.tapTarget + 4,
              child: FilledButton(
                onPressed: _submit,
                child: Text(widget.editing == null ? 'Add rule' : 'Save rule'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
