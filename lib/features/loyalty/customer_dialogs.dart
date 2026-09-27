import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../data/supabase/customers_repository.dart';

/// What the edit dialog hands back. A field left blank clears it.
typedef CustomerEdit = ({String? name, String? phone, String? email});

/// Name, phone, email — the three things a regular is known by at the counter.
/// Returns null when dismissed.
Future<CustomerEdit?> showEditCustomerDialog(
  BuildContext context,
  CrmCustomer customer,
) => showDialog<CustomerEdit>(
  context: context,
  builder: (_) => _EditCustomerDialog(customer: customer),
);

/// Pick which *other* customer this one folds into. Returns the id of the
/// customer to keep, or null when dismissed.
Future<String?> showMergeCustomerDialog(
  BuildContext context,
  CrmCustomer customer,
  List<CrmCustomer> others,
) => showDialog<String>(
  context: context,
  builder: (_) => _MergeCustomerDialog(
    customer: customer,
    others: others.where((o) => o.id != customer.id).toList(),
  ),
);

/// Spells out what goes and what stays before a delete. Returns true to go
/// ahead; false or null otherwise.
Future<bool> confirmDeleteCustomer(
  BuildContext context,
  CrmCustomer customer,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Delete ${customer.label}?'),
      content: const Text(
        'Past orders keep their totals but lose the name. Points and the '
        'points history go. This cannot be undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(dialogContext).colorScheme.error,
            foregroundColor: Theme.of(dialogContext).colorScheme.onError,
          ),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return ok ?? false;
}

class _EditCustomerDialog extends StatefulWidget {
  const _EditCustomerDialog({required this.customer});

  final CrmCustomer customer;

  @override
  State<_EditCustomerDialog> createState() => _EditCustomerDialogState();
}

class _EditCustomerDialogState extends State<_EditCustomerDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.customer.name ?? '',
  );
  late final TextEditingController _phone = TextEditingController(
    text: widget.customer.phone ?? '',
  );
  late final TextEditingController _email = TextEditingController(
    text: widget.customer.email ?? '',
  );

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  bool get _valid =>
      _name.text.trim().isNotEmpty ||
      _phone.text.trim().isNotEmpty ||
      _email.text.trim().isNotEmpty;

  String? _clean(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? null : t;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit customer'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              maxLength: 80,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: !_valid
              ? null
              : () => Navigator.of(context).pop((
                  name: _clean(_name),
                  phone: _clean(_phone),
                  email: _clean(_email),
                )),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _MergeCustomerDialog extends StatefulWidget {
  const _MergeCustomerDialog({required this.customer, required this.others});

  final CrmCustomer customer;
  final List<CrmCustomer> others;

  @override
  State<_MergeCustomerDialog> createState() => _MergeCustomerDialogState();
}

class _MergeCustomerDialogState extends State<_MergeCustomerDialog> {
  final _search = TextEditingController();
  String? _picked;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = _search.text.trim().toLowerCase();
    final shown = q.isEmpty
        ? widget.others
        : widget.others
              .where((o) => o.describe.toLowerCase().contains(q))
              .toList();

    return AlertDialog(
      title: Text('Merge ${widget.customer.label}'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pick the customer to keep. Their orders, reservations, '
              'feedback and points move to the one you keep; this record '
              'is removed.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _search,
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search by name, phone or email',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: shown.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        widget.others.isEmpty
                            ? 'No other customers to merge into.'
                            : 'Nobody matches.',
                        style: theme.textTheme.bodySmall,
                      ),
                    )
                  : RadioGroup<String>(
                      groupValue: _picked,
                      onChanged: (v) => setState(() => _picked = v),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: shown.length,
                        itemBuilder: (_, i) {
                          final o = shown[i];
                          return RadioListTile<String>(
                            value: o.id,
                            title: Text(o.label),
                            subtitle: o.describe == o.label
                                ? null
                                : Text(
                                    o.describe,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                            dense: true,
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, Tokens.tapTarget),
          ),
          onPressed: _picked == null
              ? null
              : () => Navigator.of(context).pop(_picked),
          child: const Text('Merge'),
        ),
      ],
    );
  }
}
