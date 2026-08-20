import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format/labels.dart';
import '../../core/format/money.dart';
import '../../core/theme/tokens.dart';
import 'bill_math.dart';
import 'bill_models.dart';
import 'checkout_adjust_sheet.dart' show SheetAction, SheetLabel;

/// What the guest sheet decided.
sealed class CustomerAction {
  const CustomerAction();
}

class AttachCustomerAction extends CustomerAction {
  const AttachCustomerAction({this.name, this.phone});

  final String? name;
  final String? phone;
}

/// Someone already in the book, picked back out of it.
class PickCustomerAction extends CustomerAction {
  const PickCustomerAction(this.customerId);

  final String customerId;
}

class RedeemPointsAction extends CustomerAction {
  const RedeemPointsAction(this.points);

  final int points;
}

/// Who the bill belongs to, and what their points are worth against it.
///
/// Attaching a guest is also what makes "leave it on the tab" honest: an unpaid
/// bill under nobody's name is a bill nobody can be asked to settle.
/// [search] is how the sheet reaches the tenant's book — passed in rather than
/// read off a provider so the sheet stays a plain widget with no Riverpod in it.
Future<CustomerAction?> showCustomerSheet({
  required BuildContext context,
  required BillSnapshot snapshot,
  required String currency,
  Future<List<CustomerHit>> Function(String query)? search,
}) {
  return showModalBottomSheet<CustomerAction>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) =>
        _CustomerSheet(snapshot: snapshot, currency: currency, search: search),
  );
}

class _CustomerSheet extends StatefulWidget {
  const _CustomerSheet({
    required this.snapshot,
    required this.currency,
    this.search,
  });

  final BillSnapshot snapshot;
  final String currency;
  final Future<List<CustomerHit>> Function(String query)? search;

  @override
  State<_CustomerSheet> createState() => _CustomerSheetState();
}

class _CustomerSheetState extends State<_CustomerSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.snapshot.customer?.name ?? '',
  );
  late final TextEditingController _phone = TextEditingController(
    text: widget.snapshot.customer?.phone ?? '',
  );
  final _points = TextEditingController();
  final _search = TextEditingController();

  String? _error;

  List<CustomerHit> _hits = const [];
  bool _searching = false;

  /// Only the newest search may write [_hits]. Typing fast fires several, and
  /// they come back out of order — an older, slower one landing last would put
  /// results for an abandoned query under the cashier's finger.
  int _searchSeq = 0;

  @override
  void initState() {
    super.initState();
    if (widget.snapshot.customer == null) _runSearch('');
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _points.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _runSearch(String query) async {
    final search = widget.search;
    if (search == null) return;
    final seq = ++_searchSeq;
    setState(() => _searching = true);
    final found = await search(query);
    if (!mounted || seq != _searchSeq) return;
    setState(() {
      _hits = found;
      _searching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customer = widget.snapshot.customer;
    final rate = widget.snapshot.settings.pointsValueCents;
    final maxPoints = customer == null
        ? 0
        : maxRedeemablePoints(
            points: customer.points,
            dueCents: widget.snapshot.dueCents,
            pointsValueCents: rate,
          );

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
            Text('Guest', style: theme.textTheme.titleMedium),

            if (customer == null && widget.search != null) ...[
              const SizedBox(height: 14),
              SheetLabel('Someone who has been in before'),
              TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                onChanged: _runSearch,
                decoration: InputDecoration(
                  labelText: 'Search guests',
                  hintText: 'Name or phone',
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 4),
              _CustomerHits(
                hits: _hits,
                searching: _searching,
                currency: widget.currency,
                pointsValueCents: rate,
                onPick: (hit) =>
                    Navigator.of(context).pop(PickCustomerAction(hit.id)),
              ),
            ],

            const SizedBox(height: 14),
            SheetLabel(
              customer == null && widget.search != null
                  ? 'Or someone new'
                  : 'Who this bill is for',
            ),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Name',
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone',
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            SheetAction(
              label: customer == null ? 'Attach guest' : 'Update guest',
              onPressed: () {
                final name = _name.text.trim();
                final phone = _phone.text.trim();
                if (name.isEmpty && phone.isEmpty) {
                  return setState(
                    () => _error = 'Enter a name or a phone number.',
                  );
                }
                Navigator.of(context).pop(
                  AttachCustomerAction(
                    name: name.isEmpty ? null : name,
                    phone: phone.isEmpty ? null : phone,
                  ),
                );
              },
            ),

            if (customer != null) ...[
              const SizedBox(height: 18),
              SheetLabel('Loyalty points'),
              Text(
                '${customer.points} pts, worth about '
                '${money(customer.points * (rate < 1 ? 1 : rate), widget.currency)}',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              if (maxPoints <= 0)
                Text(
                  customer.points <= 0
                      ? 'No points to redeem.'
                      : 'Their points are worth less than one whole unit of '
                            'what is owed.',
                  style: theme.textTheme.bodySmall,
                )
              else ...[
                TextField(
                  controller: _points,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: 'Points to use (up to $maxPoints)',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                SheetAction(
                  label: 'Redeem',
                  onPressed: () {
                    final entered = int.tryParse(_points.text.trim()) ?? 0;
                    if (entered <= 0) {
                      return setState(
                        () => _error = 'Enter how many points to use.',
                      );
                    }
                    // Capped here as well as server-side: a cashier who types
                    // 900 against a 300-point balance should be told, not have
                    // it silently trimmed by an RPC.
                    if (entered > maxPoints) {
                      return setState(
                        () => _error =
                            'They only have $maxPoints to spend '
                            'against this bill.',
                      );
                    }
                    Navigator.of(context).pop(RedeemPointsAction(entered));
                  },
                ),
              ],
            ],

            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],

            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The book, or as much of it as fits — tap a row to put the bill on them.
///
/// Scroll-capped rather than endless: a sheet whose list grows past the screen
/// pushes the "or someone new" fields out of reach, and a cashier who can't see
/// them starts typing into the search box instead.
class _CustomerHits extends StatelessWidget {
  const _CustomerHits({
    required this.hits,
    required this.searching,
    required this.currency,
    required this.pointsValueCents,
    required this.onPick,
  });

  final List<CustomerHit> hits;
  final bool searching;
  final String currency;
  final int pointsValueCents;
  final void Function(CustomerHit) onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (hits.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          searching ? 'Looking…' : 'Nobody by that name or number yet.',
          style: theme.textTheme.bodySmall,
        ),
      );
    }

    final rate = pointsValueCents < 1 ? 1 : pointsValueCents;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 260),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: hits.length,
        itemBuilder: (context, i) {
          final hit = hits[i];
          return ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            minVerticalPadding: 8,
            title: Text(hit.label),
            subtitle: Text(
              hit.phone != null && hit.name != null
                  ? '${hit.phone} · ${hit.points} pts, worth about '
                        '${money(hit.points * rate, currency)}'
                  : '${hit.points} pts, worth about '
                        '${money(hit.points * rate, currency)}',
            ),
            trailing: TextButton(
              onPressed: () => onPick(hit),
              style: TextButton.styleFrom(
                minimumSize: const Size(0, Tokens.tapTarget),
              ),
              child: const Text('Attach'),
            ),
            onTap: () => onPick(hit),
          );
        },
      ),
    );
  }
}

/// Fired orders with no bill of their own, offered for merging onto this one.
class MergeCard extends StatelessWidget {
  const MergeCard({super.key, required this.orders, required this.onMerge});

  final List<MergeableOrder> orders;
  final void Function(MergeableOrder)? onMerge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Another round or another table can join this bill.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 6),
        for (final o in orders)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(
              o.tableLabel != null ? 'Table ${o.tableLabel}' : 'Takeaway',
            ),
            // Through the label map, never a string replace — `in_kitchen` is
            // "In kitchen", not "in kitchen".
            subtitle: Text(orderStatusLabel(o.status)),
            trailing: TextButton(
              onPressed: onMerge == null ? null : () => onMerge!(o),
              style: TextButton.styleFrom(
                minimumSize: const Size(0, Tokens.tapTarget),
              ),
              child: const Text('Add'),
            ),
          ),
      ],
    );
  }
}
