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

class RedeemPointsAction extends CustomerAction {
  const RedeemPointsAction(this.points);

  final int points;
}

/// Who the bill belongs to, and what their points are worth against it.
///
/// Attaching a guest is also what makes "leave it on the tab" honest: an unpaid
/// bill under nobody's name is a bill nobody can be asked to settle.
Future<CustomerAction?> showCustomerSheet({
  required BuildContext context,
  required BillSnapshot snapshot,
  required String currency,
}) {
  return showModalBottomSheet<CustomerAction>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _CustomerSheet(snapshot: snapshot, currency: currency),
  );
}

class _CustomerSheet extends StatefulWidget {
  const _CustomerSheet({required this.snapshot, required this.currency});

  final BillSnapshot snapshot;
  final String currency;

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

  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _points.dispose();
    super.dispose();
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

            const SizedBox(height: 14),
            SheetLabel('Who this bill is for'),
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
