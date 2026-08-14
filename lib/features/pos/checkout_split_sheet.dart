import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../core/format/labels.dart';
import '../../core/format/money.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/choice_chip.dart';
import 'bill_math.dart';
import 'bill_models.dart';
import 'checkout_adjust_sheet.dart' show SheetAction, SheetLabel;
import 'checkout_payment_sheet.dart' show paymentMethods;

/// One share of a split, ready to be recorded.
class SplitPayment {
  const SplitPayment({
    required this.method,
    required this.amountCents,
    required this.idempotencyKey,
  });

  final String method;
  final int amountCents;

  /// Deterministic per slot — see [splitKey].
  final String idempotencyKey;
}

/// Split the check.
///
/// There is no split *schema*: each share is an ordinary `record_payment`
/// against the one bill, and the server rolls it open → partial → paid and
/// clamps the last share to what is left. What makes it safe is the key: the
/// same slot always sends the same one, so a double-tap on share two dedups
/// instead of charging twice, while two shares of equal value still differ.
///
/// The sheet stays open between shares and asks its caller to record each one,
/// so the balance it shows is the server's after every share rather than a
/// local subtraction.
Future<void> showSplitSheet({
  required BuildContext context,
  required BillSnapshot Function() snapshot,
  required String currency,
  required Future<String?> Function(SplitPayment) onPay,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) =>
        _SplitSheet(snapshot: snapshot, currency: currency, onPay: onPay),
  );
}

enum _SplitMode { equal, item, tender }

class _SplitSheet extends StatefulWidget {
  const _SplitSheet({
    required this.snapshot,
    required this.currency,
    required this.onPay,
  });

  /// Read fresh on every rebuild: another terminal can discount this bill while
  /// the sheet is open, and the share must be taken from the live figure.
  final BillSnapshot Function() snapshot;

  final String currency;

  /// Records one share. Returns an error message, or null when it landed.
  final Future<String?> Function(SplitPayment) onPay;

  @override
  State<_SplitSheet> createState() => _SplitSheetState();
}

class _SplitSheetState extends State<_SplitSheet> {
  static const _uuid = Uuid();

  final _tender = TextEditingController();

  _SplitMode _mode = _SplitMode.equal;
  String _method = 'cash';
  bool _busy = false;
  String? _error;

  // Equal split.
  int _ways = 2;
  List<int>? _shares;
  int _paidShares = 0;

  // By item.
  final _selected = <String>{};
  int _payerIdx = 0;

  // By tender.
  int _tenderIdx = 0;

  /// Minted on the gesture that starts a split, never in `build` — a nonce that
  /// changed on rebuild would hand every retry a fresh key, which is exactly
  /// the double charge the scheme prevents.
  String? _nonce;

  @override
  void dispose() {
    _tender.dispose();
    super.dispose();
  }

  String _keyFor(String mode, int slot) {
    final nonce = _nonce ??= _uuid.v4();
    return splitKey(
      billId: widget.snapshot().bill.id,
      mode: mode,
      nonce: nonce,
      slot: slot,
    );
  }

  Future<void> _pay(
    int cents,
    String key, {
    required VoidCallback onLanded,
  }) async {
    if (_busy || cents <= 0) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    // The bill may have moved since this share was worked out. Never send more
    // than is owed — the server clamps too, but a clamped payment reads to the
    // cashier as if the split was wrong.
    final due = widget.snapshot().dueCents;
    final amount = cents < due ? cents : due;

    // Nothing left: the counter settled it while this sheet was open. Say that,
    // rather than calling `record_payment` with zero and showing "enter an
    // amount" to a cashier who entered one.
    if (amount <= 0) {
      setState(() {
        _busy = false;
        _error =
            'This bill has been settled somewhere else. Close this and pull '
            'down to refresh.';
      });
      return;
    }
    final error = await widget.onPay(
      SplitPayment(method: _method, amountCents: amount, idempotencyKey: key),
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
      if (error == null) onLanded();
    });
    if (error == null && widget.snapshot().dueCents == 0 && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final snapshot = widget.snapshot();
    final due = snapshot.dueCents;

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
            Text('Split the check', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '${money(due, widget.currency)} still owed',
              style: theme.textTheme.bodySmall,
            ),

            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                AppChoiceChip(
                  label: 'Equally',
                  selected: _mode == _SplitMode.equal,
                  showCheck: true,
                  onSelect: () => setState(() => _mode = _SplitMode.equal),
                ),
                AppChoiceChip(
                  label: 'By item',
                  selected: _mode == _SplitMode.item,
                  showCheck: true,
                  onSelect: () => setState(() => _mode = _SplitMode.item),
                ),
                AppChoiceChip(
                  label: 'By tender',
                  selected: _mode == _SplitMode.tender,
                  showCheck: true,
                  onSelect: () => setState(() => _mode = _SplitMode.tender),
                ),
              ],
            ),

            const SizedBox(height: 16),
            SheetLabel('Paid with'),
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

            const SizedBox(height: 16),
            switch (_mode) {
              _SplitMode.equal => _equalBody(due),
              _SplitMode.item => _itemBody(snapshot, due),
              _SplitMode.tender => _tenderBody(),
            },

            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],

            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _equalBody(int due) {
    final shares = _shares;
    final theme = Theme.of(context);

    if (shares == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: _ways <= 2 ? null : () => setState(() => _ways -= 1),
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Expanded(
                child: Text(
                  '$_ways ways',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              IconButton(
                onPressed: _ways >= 12
                    ? null
                    : () => setState(() => _ways += 1),
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SheetAction(
            label: 'Split $_ways ways',
            onPressed: due <= 0
                ? null
                : () => setState(() {
                    // The nonce belongs to this attempt at splitting, and is
                    // minted here — in a gesture — for the reason above.
                    _nonce = const Uuid().v4();
                    _shares = distributeCents(due, _ways);
                    _paidShares = 0;
                  }),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < shares.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Share ${i + 1}${i < _paidShares ? ' · paid' : ''}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                Text(
                  money(shares[i], widget.currency),
                  style: (theme.textTheme.bodyMedium ?? const TextStyle())
                      .copyWith(
                        decoration: i < _paidShares
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 10),
        SheetAction(
          label: _paidShares >= shares.length
              ? 'All shares taken'
              : 'Take share ${_paidShares + 1} '
                    '(${money(shares[_paidShares], widget.currency)})',
          onPressed: _busy || _paidShares >= shares.length
              ? null
              : () => _pay(
                  shares[_paidShares],
                  _keyFor('eq', _paidShares),
                  onLanded: () => _paidShares += 1,
                ),
        ),
        TextButton(
          onPressed: _busy
              ? null
              : () => setState(() {
                  _shares = null;
                  _paidShares = 0;
                }),
          child: const Text('Start the split again'),
        ),
      ],
    );
  }

  Widget _itemBody(BillSnapshot snapshot, int due) {
    final linesTotal = snapshot.itemTotalCents;
    final selectedSubtotal = snapshot.lines
        .where((l) => _selected.contains(l.id))
        .fold(0, (n, l) => n + l.totalCents);
    // Proportional to the WHOLE bill, so tax, service and discount ride along
    // rather than falling on whoever pays last.
    final share = itemShareCents(
      selectedSubtotalCents: selectedSubtotal,
      linesTotalCents: linesTotal,
      totalCents: snapshot.bill.totalCents,
      dueCents: due,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final line in snapshot.lines)
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: _selected.contains(line.id),
            onChanged: _busy
                ? null
                : (on) => setState(() {
                    if (on ?? false) {
                      _selected.add(line.id);
                    } else {
                      _selected.remove(line.id);
                    }
                  }),
            title: Text(line.description),
            subtitle: Text(money(line.totalCents, widget.currency)),
          ),
        const SizedBox(height: 10),
        SheetAction(
          label: 'Take ${money(share, widget.currency)}',
          onPressed: _busy || share <= 0
              ? null
              : () => _pay(
                  share,
                  _keyFor('item', _payerIdx),
                  onLanded: () {
                    // Only a landed payment advances the payer, so a retry of a
                    // failed share reuses its key.
                    _payerIdx += 1;
                    _selected.clear();
                  },
                ),
        ),
      ],
    );
  }

  Widget _tenderBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _tender,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Amount on this tender',
            prefixText: '${widget.currency} ',
          ),
        ),
        const SizedBox(height: 10),
        SheetAction(
          label: 'Take it',
          onPressed: _busy
              ? null
              : () {
                  final amount = double.tryParse(_tender.text.trim());
                  if (amount == null || amount <= 0) {
                    setState(() => _error = 'Enter a valid amount.');
                    return;
                  }
                  _pay(
                    (amount * 100).round(),
                    _keyFor('tender', _tenderIdx),
                    onLanded: () {
                      _tenderIdx += 1;
                      _tender.clear();
                    },
                  );
                },
        ),
        const SizedBox(height: 6),
        Text(
          'Each tender is recorded on its own. The bill closes when they add '
          'up to the total.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// The refund flow: an amount, a reason, and a confirmation that names both.
///
/// Deliberately plainer than the split sheet. `refund_payment` carries no
/// idempotency key, so there is no safe automatic retry — the dialog and the
/// caller's busy guard are the whole protection.
Future<({int amountCents, String reason})?> showRefundSheet({
  required BuildContext context,
  required int paidCents,
  required String currency,
}) {
  return showModalBottomSheet<({int amountCents, String reason})>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _RefundSheet(paidCents: paidCents, currency: currency),
  );
}

class _RefundSheet extends StatefulWidget {
  const _RefundSheet({required this.paidCents, required this.currency});

  final int paidCents;
  final String currency;

  @override
  State<_RefundSheet> createState() => _RefundSheetState();
}

class _RefundSheetState extends State<_RefundSheet> {
  late final TextEditingController _amount = TextEditingController(
    text: (widget.paidCents / 100).toStringAsFixed(2),
  );
  final _reason = TextEditingController();

  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amount.text.trim());
    final reason = _reason.text.trim();
    if (amount == null || amount <= 0) {
      return setState(() => _error = 'Enter how much to give back.');
    }
    if (reason.isEmpty) {
      return setState(() => _error = 'A refund needs a reason.');
    }
    final cents = (amount * 100).round();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Refund this?'),
        content: Text(
          '${money(cents, widget.currency)} goes back to the guest. This '
          "can't be undone, and a second attempt would refund it twice.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Refund ${money(cents, widget.currency)}'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    Navigator.of(context).pop((amountCents: cents, reason: reason));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Refund', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            '${money(widget.paidCents, widget.currency)} was taken on this '
            'bill.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            decoration: InputDecoration(
              labelText: 'Amount',
              prefixText: '${widget.currency} ',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _reason,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Reason'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _submit,
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, Tokens.tapTarget),
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
            ),
            child: const Text('Refund'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}
