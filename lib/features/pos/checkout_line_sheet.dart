import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format/money.dart';
import '../../core/widgets/choice_chip.dart';
import 'bill_models.dart';
import 'checkout_adjust_sheet.dart';
import 'void_reason_dialog.dart';

/// What can be done to one line of the bill.
///
/// The web puts a discount box in a table cell, which works with a counter
/// keyboard and a mouse. At 360dp that cell is a target nobody can hit
/// mid-service, so the line opens this instead — deliberately different, same
/// two RPCs behind it.
Future<BillAdjustment?> showLineSheet({
  required BuildContext context,
  required BillLine line,
  required String currency,
  required bool canDiscount,
  required bool canVoid,
}) {
  return showModalBottomSheet<BillAdjustment>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _LineSheet(
      line: line,
      currency: currency,
      canDiscount: canDiscount,
      canVoid: canVoid,
    ),
  );
}

class _LineSheet extends StatefulWidget {
  const _LineSheet({
    required this.line,
    required this.currency,
    required this.canDiscount,
    required this.canVoid,
  });

  final BillLine line;
  final String currency;
  final bool canDiscount;
  final bool canVoid;

  @override
  State<_LineSheet> createState() => _LineSheetState();
}

class _LineSheetState extends State<_LineSheet> {
  final _value = TextEditingController();
  final _reason = TextEditingController();

  String _type = 'percent';
  String? _error;

  @override
  void dispose() {
    _value.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _submitDiscount() {
    final orderItemId = widget.line.orderItemId;
    if (orderItemId == null) return;

    final value = num.tryParse(_value.text.trim());
    if (value == null || value <= 0) {
      return setState(() => _error = 'Enter how much to take off.');
    }
    if (_type == 'percent' && value > 100) {
      return setState(
        () => _error = "A percentage discount can't be more than 100%.",
      );
    }
    Navigator.of(context).pop(
      DiscountAdjustment(
        type: _type,
        value: value,
        reason: _reason.text.trim().isEmpty ? null : _reason.text.trim(),
        orderItemId: orderItemId,
      ),
    );
  }

  Future<void> _submitVoid() async {
    final orderItemId = widget.line.orderItemId;
    if (orderItemId == null) return;

    final reason = await showVoidReasonDialog(
      context: context,
      title: 'Void ${widget.line.description}?',
      body:
          'The line comes off this bill and the kitchen is told to drop it. '
          'Stock already deducted is returned.',
    );
    if (reason == null || !mounted) return;
    Navigator.of(
      context,
    ).pop(VoidLineAdjustment(orderItemId: orderItemId, reason: reason));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final line = widget.line;

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
            Text(line.description, style: theme.textTheme.titleMedium),
            Text(
              '${line.qty} × ${money(line.unitPriceCents, widget.currency)}'
              ' = ${money(line.totalCents, widget.currency)}',
              style: theme.textTheme.bodySmall,
            ),

            // A line `recompute_bill` wrote with no order item behind it. Both
            // RPCs here take an order-item id, so there is nothing to offer.
            if (!line.isAdjustable) ...[
              const SizedBox(height: 16),
              Text(
                "This line isn't tied to a kitchen item, so it can't be "
                'discounted or voided here. Adjust the bill instead.',
                style: theme.textTheme.bodySmall,
              ),
            ],

            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],

            if (line.isAdjustable && widget.canDiscount) ...[
              const SizedBox(height: 18),
              SheetLabel('Discount this line'),
              Row(
                children: [
                  AppChoiceChip(
                    label: '%',
                    selected: _type == 'percent',
                    onSelect: () => setState(() => _type = 'percent'),
                  ),
                  const SizedBox(width: 8),
                  AppChoiceChip(
                    label: widget.currency,
                    selected: _type == 'flat',
                    onSelect: () => setState(() => _type = 'flat'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _value,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Amount',
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _reason,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Reason (goes in the manager log)',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              SheetAction(label: 'Apply discount', onPressed: _submitDiscount),
            ],

            if (line.isAdjustable && widget.canVoid) ...[
              const SizedBox(height: 18),
              SheetAction(
                label: 'Void this line',
                destructive: true,
                onPressed: _submitVoid,
              ),
            ],

            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}
