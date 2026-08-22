import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/print/reprint_actions.dart';
import '../tenant/tenant_providers.dart';

/// Put the day close on the thermal roll.
///
/// Gated on `reports.view` because the RPC raises without it, and a button that
/// always fails is worse than no button. The queue itself needs no changes: the
/// drainer never reads a job's document type, so a `day_report` job is claimed
/// and printed by whichever device is draining, exactly like a bill.
class PrintDayReportButton extends ConsumerStatefulWidget {
  const PrintDayReportButton({super.key, required this.day});

  /// The business day, `YYYY-MM-DD`, as the server resolved it.
  final String day;

  @override
  ConsumerState<PrintDayReportButton> createState() =>
      _PrintDayReportButtonState();
}

class _PrintDayReportButtonState extends ConsumerState<PrintDayReportButton> {
  bool _busy = false;

  Future<void> _print() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final message = await printDayReport(ref, widget.day);
      if (!mounted) return;
      // Success and failure arrive the same way — the sentence *is* the
      // outcome, so there is never a silent tap.
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(hasPermissionProvider('reports.view'))) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _busy ? null : _print,
        icon: const Icon(Icons.print_outlined),
        label: Text(_busy ? 'Queueing…' : 'Print day close (Z)'),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      ),
    );
  }
}
