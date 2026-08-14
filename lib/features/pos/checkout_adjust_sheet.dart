import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format/money.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/choice_chip.dart';
import 'bill_math.dart';
import 'bill_models.dart';

/// What the adjustments sheet decided. The screen performs it, so every write
/// on this page goes through the one `mutate` path and the one busy guard.
sealed class BillAdjustment {
  const BillAdjustment();
}

class DiscountAdjustment extends BillAdjustment {
  const DiscountAdjustment({
    required this.type,
    required this.value,
    this.reason,
    this.orderItemId,
  });

  /// `percent` or `flat`.
  final String type;

  /// Percentage points, or whole currency units — the RPC's own shape.
  final num value;

  final String? reason;

  /// Null for a bill-level discount.
  final String? orderItemId;
}

/// Take a discount back off. Null [orderItemId] means the bill's staff
/// discount; a coupon is never removed this way.
class RemoveDiscountAdjustment extends BillAdjustment {
  const RemoveDiscountAdjustment({this.orderItemId});

  final String? orderItemId;
}

class CouponAdjustment extends BillAdjustment {
  const CouponAdjustment(this.code);

  final String code;
}

class ChargeAdjustment extends BillAdjustment {
  const ChargeAdjustment({required this.label, required this.amountCents});

  final String label;
  final int amountCents;
}

class RemoveChargeAdjustment extends BillAdjustment {
  const RemoveChargeAdjustment(this.chargeId);

  final String chargeId;
}

class ExtrasAdjustment extends BillAdjustment {
  const ExtrasAdjustment({
    required this.tipCents,
    required this.roundingCents,
    this.note,
  });

  final int tipCents;
  final int roundingCents;
  final String? note;
}

class ComplimentaryAdjustment extends BillAdjustment {
  const ComplimentaryAdjustment(this.reason);

  final String reason;
}

class VoidLineAdjustment extends BillAdjustment {
  const VoidLineAdjustment({required this.orderItemId, required this.reason});

  final String orderItemId;
  final String reason;
}

/// Everything that changes what the bill *is*, rather than what has been paid.
///
/// One sheet rather than controls scattered through the totals card: at 360dp a
/// discount field, a coupon box and a charge form inline would push the total —
/// the figure the cashier is reading out loud — off the screen.
Future<BillAdjustment?> showAdjustmentsSheet({
  required BuildContext context,
  required BillSnapshot snapshot,
  required String currency,
  required bool canDiscount,
  required bool canCharge,
  required bool canTakePayment,
}) {
  return showModalBottomSheet<BillAdjustment>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _AdjustSheet(
      snapshot: snapshot,
      currency: currency,
      canDiscount: canDiscount,
      canCharge: canCharge,
      canTakePayment: canTakePayment,
    ),
  );
}

class _AdjustSheet extends StatefulWidget {
  const _AdjustSheet({
    required this.snapshot,
    required this.currency,
    required this.canDiscount,
    required this.canCharge,
    required this.canTakePayment,
  });

  final BillSnapshot snapshot;
  final String currency;

  /// Manager **and** `order.discount` — the discount RPCs check both.
  final bool canDiscount;

  /// `order.discount` alone — charges and complimentary check the key only.
  final bool canCharge;

  /// `payment.take` — coupon, tip, round off, remark.
  final bool canTakePayment;

  @override
  State<_AdjustSheet> createState() => _AdjustSheetState();
}

class _AdjustSheetState extends State<_AdjustSheet> {
  final _discount = TextEditingController();
  final _discountReason = TextEditingController();
  final _coupon = TextEditingController();
  final _chargeLabel = TextEditingController();
  final _chargeAmount = TextEditingController();
  late final TextEditingController _tip = TextEditingController(
    text: (widget.snapshot.bill.tipCents / 100).toStringAsFixed(2),
  );
  late final TextEditingController _note = TextEditingController(
    text: widget.snapshot.bill.note ?? '',
  );

  String _discountType = 'percent';
  String? _error;

  @override
  void dispose() {
    _discount.dispose();
    _discountReason.dispose();
    _coupon.dispose();
    _chargeLabel.dispose();
    _chargeAmount.dispose();
    _tip.dispose();
    _note.dispose();
    super.dispose();
  }

  void _finish(BillAdjustment adjustment) =>
      Navigator.of(context).pop(adjustment);

  void _fail(String message) => setState(() => _error = message);

  /// "20%" or "NPR 150" — [DiscountRow.value] is percentage points for
  /// `percent` and whole currency units for `flat`, never cents.
  String _discountLabel(DiscountRow d) => d.isPercent
      ? '${d.value}%'
      : money((d.value * 100).round(), widget.currency);

  void _submitDiscount() {
    final value = num.tryParse(_discount.text.trim());
    if (value == null || value <= 0) {
      return _fail('Enter how much to take off.');
    }
    if (_discountType == 'percent' && value > 100) {
      return _fail("A percentage discount can't be more than 100%.");
    }
    _finish(
      DiscountAdjustment(
        type: _discountType,
        value: value,
        reason: _discountReason.text.trim().isEmpty
            ? null
            : _discountReason.text.trim(),
      ),
    );
  }

  void _submitCharge() {
    final label = _chargeLabel.text.trim();
    final amount = double.tryParse(_chargeAmount.text.trim());
    if (label.isEmpty) return _fail('Give the charge a name.');
    if (amount == null || amount <= 0) {
      return _fail('Enter what the charge comes to.');
    }
    _finish(
      ChargeAdjustment(label: label, amountCents: (amount * 100).round()),
    );
  }

  void _submitExtras({int? roundingOverride}) {
    final tip = double.tryParse(_tip.text.trim()) ?? 0;
    if (tip < 0) return _fail("A tip can't be negative.");
    final note = _note.text.trim();
    _finish(
      ExtrasAdjustment(
        tipCents: (tip * 100).round(),
        roundingCents: roundingOverride ?? widget.snapshot.bill.roundingCents,
        note: note.isEmpty ? null : note,
      ),
    );
  }

  Future<void> _submitComplimentary() async {
    final reason = await showReasonDialog(
      context: context,
      title: 'On the house?',
      body:
          'The whole bill comes off as a discount, with your name and this '
          'reason on it. Nothing is collected.',
      confirmLabel: 'Make it complimentary',
    );
    if (reason == null || !mounted) return;
    _finish(ComplimentaryAdjustment(reason));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final existingDiscount = widget.snapshot.staffBillDiscount;
    final bill = widget.snapshot.bill;
    final roundOff = roundOffCents(
      totalCents: bill.totalCents,
      roundingCents: bill.roundingCents,
    );
    final rounded = bill.roundingCents != 0;

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
            Text('Adjust this bill', style: theme.textTheme.titleMedium),

            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],

            if (widget.canDiscount) ...[
              const SizedBox(height: 18),
              SheetLabel('Discount the whole bill'),
              // Applying replaces whatever is on the bill, so say so rather than
              // letting a cashier assume the new one stacks on the old.
              if (existingDiscount != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Now: ${_discountLabel(existingDiscount)}'
                        '${existingDiscount.reason == null ? '' : ' — ${existingDiscount.reason}'}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('Remove'),
                      onPressed: () =>
                          _finish(const RemoveDiscountAdjustment()),
                    ),
                  ],
                ),
              ],
              Row(
                children: [
                  AppChoiceChip(
                    label: '%',
                    selected: _discountType == 'percent',
                    onSelect: () => setState(() => _discountType = 'percent'),
                  ),
                  const SizedBox(width: 8),
                  AppChoiceChip(
                    label: widget.currency,
                    selected: _discountType == 'flat',
                    onSelect: () => setState(() => _discountType = 'flat'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _discount,
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
                controller: _discountReason,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Reason (goes in the manager log)',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              SheetAction(
                label: existingDiscount == null
                    ? 'Apply discount'
                    : 'Replace discount',
                onPressed: _submitDiscount,
              ),
            ],

            if (widget.canTakePayment) ...[
              const SizedBox(height: 18),
              SheetLabel('Coupon'),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _coupon,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Code',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SheetAction(
                    label: 'Apply',
                    onPressed: () {
                      final code = _coupon.text.trim();
                      if (code.isEmpty) return _fail('Enter a coupon code.');
                      _finish(CouponAdjustment(code));
                    },
                  ),
                ],
              ),
            ],

            if (widget.canCharge) ...[
              const SizedBox(height: 18),
              SheetLabel('Extra charge'),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _chargeLabel,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'What for',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _chargeAmount,
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
              SheetAction(label: 'Add charge', onPressed: _submitCharge),

              if (widget.snapshot.charges.isNotEmpty) ...[
                const SizedBox(height: 10),
                for (final c in widget.snapshot.charges)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(c.label),
                    subtitle: Text(money(c.amountCents, widget.currency)),
                    trailing: IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Remove ${c.label}',
                      onPressed: () => _finish(RemoveChargeAdjustment(c.id)),
                    ),
                  ),
              ],
            ],

            if (widget.canTakePayment) ...[
              const SizedBox(height: 18),
              SheetLabel('Tip, round off and remark'),
              TextField(
                controller: _tip,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                decoration: InputDecoration(
                  labelText: 'Tip',
                  prefixText: '${widget.currency} ',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _note,
                textCapitalization: TextCapitalization.sentences,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Remark on the invoice',
                  isDense: true,
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: SheetAction(label: 'Save', onPressed: _submitExtras),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SheetAction(
                      // Undo sends zero; applying sends the shortfall. Both go
                      // through the same call, so the totals card never has to
                      // guess which happened.
                      label: rounded ? 'Undo round off' : 'Round off',
                      onPressed: roundOff == 0 && !rounded
                          ? null
                          : () => _submitExtras(
                              roundingOverride: rounded ? 0 : roundOff,
                            ),
                    ),
                  ),
                ],
              ),
            ],

            if (widget.canCharge) ...[
              const SizedBox(height: 18),
              SheetAction(
                label: 'On the house',
                destructive: true,
                onPressed: _submitComplimentary,
              ),
            ],

            const SizedBox(height: 8),
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

/// A confirm-with-a-reason dialog.
///
/// **Owns its controller**, for the reason spelled out in
/// `void_reason_dialog.dart`: a caller that disposed one around the `await`
/// would kill it a frame before the field unmounts, and take the app with it.
Future<String?> showReasonDialog({
  required BuildContext context,
  required String title,
  required String body,
  required String confirmLabel,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) =>
        _ReasonDialog(title: title, body: body, confirmLabel: confirmLabel),
  );
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({
    required this.title,
    required this.body,
    required this.confirmLabel,
  });

  final String title;
  final String body;
  final String confirmLabel;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _reason.text.trim();
    if (text.isEmpty) return;
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.body),
          const SizedBox(height: 14),
          TextField(
            controller: _reason,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(labelText: 'Reason'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}

class SheetLabel extends StatelessWidget {
  const SheetLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: Theme.of(context).textTheme.labelMedium),
  );
}

class SheetAction extends StatelessWidget {
  const SheetAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.destructive = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FilledButton.tonal(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, Tokens.tapTarget),
        foregroundColor: destructive ? scheme.error : null,
      ),
      child: Text(label),
    );
  }
}
