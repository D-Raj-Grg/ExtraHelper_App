import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format/labels.dart';
import '../../core/format/money.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/choice_chip.dart';
import 'bill_models.dart';

/// How the money is arriving.
///
/// `online` is deliberately absent. The web charges a card through a
/// server-side gateway adapter that has no RPC behind it, so an app offering
/// "Card (online)" would record a payment it never collected. A card taken on a
/// terminal at the table is `card`, the same as the web's offline card path.
///
/// eSewa, FonePay and a bank transfer are safe here for the opposite reason:
/// nothing charges them. The guest scans a QR, shows the confirmation, and the
/// cashier records what arrived — the same trust as a terminal card. That also
/// means they queue offline exactly like cash.
const paymentMethods = ['cash', 'card', 'esewa', 'fonepay', 'bank', 'wallet'];

/// Methods that carry a guest-side transaction id worth keeping. Cash has none;
/// for the rest it is what makes the payment reconcilable against the
/// provider's own statement later.
const _referenceMethods = {'card', 'esewa', 'fonepay', 'bank', 'wallet'};

bool paymentMethodTakesReference(String method) =>
    _referenceMethods.contains(method);

/// The server caps `payments.reference`; mirror it so the field can't overrun.
const paymentReferenceMax = 120;

/// What the cashier decided to do with the balance.
enum PaymentMode {
  /// Take everything still owed.
  full,

  /// Take part of it. The bill stays open for the rest.
  partial,

  /// Take nothing and leave it on the guest's tab.
  credit,
}

/// The result of the sheet — what to do, once the sheet is gone.
class PaymentIntent {
  const PaymentIntent.take({
    required this.method,
    required this.amountCents,
    this.reference,
  }) : mode = PaymentMode.full,
       isCredit = false;

  const PaymentIntent.partial({
    required this.method,
    required this.amountCents,
    this.reference,
  }) : mode = PaymentMode.partial,
       isCredit = false;

  const PaymentIntent.credit()
    : mode = PaymentMode.credit,
      method = 'cash',
      amountCents = 0,
      reference = null,
      isCredit = true;

  final PaymentMode mode;
  final String method;
  final int amountCents;

  /// The guest's transaction id, when they had one. Null for cash.
  final String? reference;
  final bool isCredit;
}

/// Ask what to take, and how.
///
/// The sheet only *decides*. The write happens on the checkout screen, which
/// owns the idempotency key ring — a sheet that took the payment itself would
/// mint a fresh key each time it opened, and a cashier who backed out and came
/// straight back in would charge the guest twice.
Future<PaymentIntent?> showPaymentSheet({
  required BuildContext context,
  required BillSnapshot snapshot,
  required String currency,
  required bool canLeaveOnTab,
}) {
  return showModalBottomSheet<PaymentIntent>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _PaymentSheet(
      snapshot: snapshot,
      currency: currency,
      canLeaveOnTab: canLeaveOnTab,
    ),
  );
}

class _PaymentSheet extends StatefulWidget {
  const _PaymentSheet({
    required this.snapshot,
    required this.currency,
    required this.canLeaveOnTab,
  });

  final BillSnapshot snapshot;
  final String currency;
  final bool canLeaveOnTab;

  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<_PaymentSheet> {
  // The sheet owns its controllers and disposes them here. A caller that
  // created and disposed them around the `await` would kill them a frame before
  // the fields unmount — see the note on `showVoidReasonDialog`.
  late final TextEditingController _amount = TextEditingController(
    text: (widget.snapshot.dueCents / 100).toStringAsFixed(2),
  );
  final _tendered = TextEditingController();
  final _reference = TextEditingController();

  PaymentMode _mode = PaymentMode.full;
  String _method = 'cash';
  String? _error;

  int get _due => widget.snapshot.dueCents;

  @override
  void dispose() {
    _amount.dispose();
    _tendered.dispose();
    _reference.dispose();
    super.dispose();
  }

  /// The amount this sheet would take, or null when the field can't be read.
  int? get _amountCents {
    if (_mode == PaymentMode.full) return _due;
    final cents = (double.tryParse(_amount.text.trim()) ?? double.nan) * 100;
    if (cents.isNaN || cents <= 0) return null;
    return cents.round();
  }

  void _submit() {
    if (_mode == PaymentMode.credit) {
      // A tab has to be on someone. Catch it here rather than popping and
      // failing behind the sheet, where the cashier has already looked away.
      if (!widget.canLeaveOnTab) {
        setState(
          () => _error = 'Attach a guest before leaving this bill unpaid.',
        );
        return;
      }
      Navigator.of(context).pop(const PaymentIntent.credit());
      return;
    }
    final cents = _amountCents;
    if (cents == null) {
      setState(() => _error = 'Enter an amount to take.');
      return;
    }
    // Only the methods that offer the field carry one out — switching to cash
    // after typing an eSewa id must not stamp that id on the cash payment.
    final typed = _reference.text.trim();
    final ref = paymentMethodTakesReference(_method) && typed.isNotEmpty
        ? typed
        : null;
    Navigator.of(context).pop(
      _mode == PaymentMode.full
          ? PaymentIntent.take(
              method: _method,
              amountCents: cents,
              reference: ref,
            )
          : PaymentIntent.partial(
              method: _method,
              amountCents: cents,
              reference: ref,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final credit = _mode == PaymentMode.credit;

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
            Text('Take payment', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '${money(_due, widget.currency)} still owed',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 14),

            _Label('How much'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                AppChoiceChip(
                  label: 'Paid in full',
                  selected: _mode == PaymentMode.full,
                  showCheck: true,
                  onSelect: () => setState(() {
                    _mode = PaymentMode.full;
                    _error = null;
                  }),
                ),
                AppChoiceChip(
                  label: 'Part payment',
                  selected: _mode == PaymentMode.partial,
                  showCheck: true,
                  onSelect: () => setState(() {
                    _mode = PaymentMode.partial;
                    _error = null;
                  }),
                ),
                // Always offered, even with no guest attached. Hiding it left
                // a cashier on a phone with no way to *see* that an unpaid tab
                // exists at all — the web shows the chip and explains the
                // missing guest instead, and so does this.
                AppChoiceChip(
                  label: 'Unpaid (credit)',
                  selected: credit,
                  showCheck: true,
                  onSelect: () => setState(() {
                    _mode = PaymentMode.credit;
                    _error = null;
                  }),
                ),
              ],
            ),

            if (credit) ...[
              const SizedBox(height: 14),
              _CreditNote(customer: widget.snapshot.customer),
            ] else ...[
              if (_mode == PaymentMode.partial) ...[
                const SizedBox(height: 14),
                TextField(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  onChanged: (_) => setState(() => _error = null),
                  decoration: InputDecoration(
                    labelText: 'Amount',
                    prefixText: '${widget.currency} ',
                  ),
                ),
              ],

              const SizedBox(height: 14),
              _Label('How'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final m in paymentMethods)
                    AppChoiceChip(
                      label: paymentMethodLabel(m),
                      selected: _method == m,
                      showCheck: true,
                      onSelect: () => setState(() => _method = m),
                    ),
                ],
              ),

              if (paymentMethodTakesReference(_method)) ...[
                const SizedBox(height: 14),
                TextField(
                  controller: _reference,
                  maxLength: paymentReferenceMax,
                  textCapitalization: TextCapitalization.characters,
                  onChanged: (_) => setState(() => _error = null),
                  decoration: const InputDecoration(
                    labelText: 'Reference (optional)',
                    helperText: 'Transaction id from the guest’s confirmation',
                    counterText: '',
                  ),
                ),
              ],

              if (_method == 'cash') ...[
                const SizedBox(height: 14),
                TextField(
                  controller: _tendered,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Cash received (optional)',
                    prefixText: '${widget.currency} ',
                  ),
                ),
                _ChangeBand(
                  tendered: _tendered.text,
                  amountCents: _amountCents,
                  currency: widget.currency,
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

            const SizedBox(height: 18),
            FilledButton(
              onPressed: _submit,
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, Tokens.tapTarget),
              ),
              child: Text(
                credit
                    ? 'Leave unpaid'
                    : 'Take ${money(_amountCents ?? 0, widget.currency)}',
              ),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Change due, or how far short the cash is.
///
/// Colour is never the signal on its own: the word and the sign carry it, which
/// is what survives greyscale and a colourblind cashier.
class _ChangeBand extends StatelessWidget {
  const _ChangeBand({
    required this.tendered,
    required this.amountCents,
    required this.currency,
  });

  final String tendered;
  final int? amountCents;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semantic;

    final handed = double.tryParse(tendered.trim());
    final owed = amountCents;
    if (handed == null || owed == null) return const SizedBox.shrink();

    final diff = (handed * 100).round() - owed;
    if (diff == 0) return const SizedBox.shrink();

    final short = diff < 0;
    final color = short ? semantic.warningText : semantic.goodText;

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Icon(
            short ? Icons.remove_circle_outline : Icons.payments_outlined,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 8),
          Text(
            short ? 'Still short' : 'Change due',
            style: theme.textTheme.labelMedium?.copyWith(color: color),
          ),
          const Spacer(),
          Text(
            '${short ? '−' : '+'} ${money(diff.abs(), currency)}',
            style: (theme.textTheme.labelLarge ?? const TextStyle())
                .copyWith(color: color)
                .tabular,
          ),
        ],
      ),
    );
  }
}

/// Says plainly that nothing is being collected.
///
/// The web's credit mode calls no RPC at all — it toasts and leaves. Copy that
/// implied money had moved would be a lie a cashier acts on.
class _CreditNote extends StatelessWidget {
  const _CreditNote({required this.customer});

  final BillCustomer? customer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final name = customer?.label;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: semantic.attention.withValues(alpha: 0.12),
        border: Border.all(color: semantic.attention.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(Tokens.radiusMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: semantic.attentionText),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name == null
                  ? 'Attach a guest to this bill first — an unpaid tab needs '
                        'someone to be on.'
                  : 'Nothing is collected. The bill stays open under $name and '
                        'waits in the Bills tab.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: Theme.of(context).textTheme.labelMedium),
  );
}
