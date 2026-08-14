/// Which printer a document is bound for.
///
/// Pure, and deliberately so: `enqueue_print_job` takes **one** printer and
/// queues **one** job, so choosing the printers is the caller's job — the web's
/// `enqueuePrint` does exactly this before it starts calling the RPC. Two
/// clients making that choice differently is how a bar ticket ends up on the
/// kitchen roll, so the rule is ported rather than re-derived, and kept where it
/// can be tested without a network.
library;

import 'print_models.dart';

/// What a KOT's row says about the ticket: the station names it, and the
/// station's own printer routes it.
class KotRouting {
  const KotRouting({required this.doc, this.branchId, this.station});

  /// `kot` or `bot`.
  final String doc;
  final String? branchId;

  /// The station's own printer, when it has one.
  final PrintTarget? station;
}

/// Read a `kots → kitchen_stations(kind, printer_id), orders(branch_id)` row.
///
/// **The station decides KOT vs BOT, not the caller.** A reprint asked for as
/// "kot" from the POS would otherwise put a kitchen header on a bar ticket.
///
/// **A station's own printer wins outright.** Splitting tickets per station is
/// the whole point of routing, so a `printer_documents` assignment must not
/// second-guess it — and it runs one copy, not the document's configured count.
KotRouting kotRoutingFrom(Map<String, dynamic>? row) {
  final station = row?['kitchen_stations'] as Map<String, dynamic>?;
  final order = row?['orders'] as Map<String, dynamic>?;
  final routed = station?['printer_id'] as String?;

  return KotRouting(
    doc: station?['kind'] == 'bar' ? 'bot' : 'kot',
    branchId: order?['branch_id'] as String?,
    station: routed == null ? null : PrintTarget(printerId: routed, copies: 1),
  );
}

/// Read `printer_documents (printer_id, copies, printers!inner(is_active,
/// branch_id))` rows for one document.
///
/// An inactive printer is skipped, and a printer tied to a branch only prints
/// that branch's orders — otherwise a second site's receipts come out here. A
/// printer with no branch prints for everyone, which is the single-site case.
///
/// `copies` travels with the target because a manual reprint has to honour
/// "two copies of every bill" exactly as auto-print does.
List<PrintTarget> printerDocumentTargets(
  Iterable<Map<String, dynamic>> rows, {
  String? branchId,
}) {
  final targets = <PrintTarget>[];
  for (final row in rows) {
    final printer = row['printers'] as Map<String, dynamic>?;
    if (printer == null || printer['is_active'] != true) continue;

    final printerBranch = printer['branch_id'] as String?;
    if (branchId != null &&
        printerBranch != null &&
        printerBranch != branchId) {
      continue;
    }

    final id = row['printer_id'] as String?;
    if (id == null) continue;
    targets.add(
      PrintTarget(printerId: id, copies: (row['copies'] as num?)?.toInt() ?? 1),
    );
  }
  return targets;
}
