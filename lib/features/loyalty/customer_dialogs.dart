import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../data/supabase/customers_repository.dart';
import '../../data/supabase/pos_repository.dart' show PosFailure;

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
///
/// [search] runs against the whole book — the duplicate is rarely on the
/// same page of the list as the guest being merged. Empty query is "the
/// newest guests"; [customer] itself is never offered.
Future<String?> showMergeCustomerDialog(
  BuildContext context,
  CrmCustomer customer, {
  required Future<List<CrmCustomer>> Function(String query) search,
}) => showDialog<String>(
  context: context,
  builder: (_) => _MergeCustomerDialog(customer: customer, search: search),
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

  /// Mirrors `update_customer`: a guest is known by a name or a phone; an
  /// email alone is not enough to find them at the counter.
  bool get _valid =>
      _name.text.trim().isNotEmpty || _phone.text.trim().isNotEmpty;

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
            if (!_valid) ...[
              const SizedBox(height: 8),
              Text(
                'Name or phone is required.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
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
  const _MergeCustomerDialog({required this.customer, required this.search});

  final CrmCustomer customer;
  final Future<List<CrmCustomer>> Function(String query) search;

  @override
  State<_MergeCustomerDialog> createState() => _MergeCustomerDialogState();
}

class _MergeCustomerDialogState extends State<_MergeCustomerDialog> {
  final _search = TextEditingController();
  Timer? _debounce;
  int _request = 0;
  List<CrmCustomer> _shown = const [];
  bool _loading = true;
  String? _error;
  String? _picked;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) _load(value.trim());
    });
  }

  /// Runs the search; a reply to an older query than the one now typed is
  /// dropped, so fast typing cannot land stale rows on top of fresh ones.
  Future<void> _load(String query) async {
    final ticket = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    List<CrmCustomer> rows;
    String? error;
    try {
      rows = await widget.search(query);
    } on PosFailure catch (e) {
      rows = const [];
      error = e.message;
    } catch (_) {
      rows = const [];
      error = "Couldn't search customers.";
    }
    if (!mounted || ticket != _request) return;
    setState(() {
      _shown = rows.where((o) => o.id != widget.customer.id).toList();
      if (_picked != null && !_shown.any((o) => o.id == _picked)) {
        _picked = null;
      }
      _error = error;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
              onChanged: _onChanged,
            ),
            const SizedBox(height: 8),
            Flexible(
              child: switch ((_loading, _error, _shown.isEmpty)) {
                (true, _, _) => const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                    child: SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
                (_, final String error, _) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    error,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
                (_, _, true) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Nobody matches.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                _ => RadioGroup<String>(
                  groupValue: _picked,
                  onChanged: (v) => setState(() => _picked = v),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _shown.length,
                    itemBuilder: (_, i) {
                      final o = _shown[i];
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
              },
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
