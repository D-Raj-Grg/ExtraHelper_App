import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/pos_repository.dart' show PosFailure, PosTransientFailure;
import '../supabase/supabase_providers.dart';
import 'print_models.dart';
import 'print_routing.dart';

/// The queue's client half.
///
/// Nothing here decides *whether* something prints. Postgres triggers queue a
/// KOT when it is created and a receipt when a bill is settled, so a phone that
/// prints is a consumer of that queue and nothing more — the same position the
/// browser worker and the headless agent are in.
///
/// Every write is an RPC. `printers`, `printer_documents` and `print_jobs` are
/// select-only under RLS on purpose.
class PrintRepository {
  const PrintRepository(this._client, this._tenantId);

  final SupabaseClient _client;
  final String _tenantId;

  static const _printerCols =
      'id, name, connection, host, port, system_name, bt_address, '
      'paper_width, render_mode, is_active, branch_id';

  Future<List<PrintPrinter>> printers() async {
    try {
      final rows = await _client
          .from('printers')
          .select(_printerCols)
          .eq('tenant_id', _tenantId)
          .order('name');
      return rows.map(PrintPrinter.fromJson).toList();
    } catch (_) {
      throw const PosTransientFailure("Couldn't load the printers.");
    }
  }

  /// The tail of the queue, newest first — what printed, what is waiting, and
  /// what failed with which message.
  Future<List<PrintJob>> jobs({int limit = 25}) async {
    try {
      final rows = await _client
          .from('print_jobs')
          .select(
            'id, doc, status, attempts, error, created_at, claimed_by, printers(name)',
          )
          .eq('tenant_id', _tenantId)
          .order('created_at', ascending: false)
          .limit(limit);
      return rows.map(PrintJob.fromJson).toList();
    } catch (_) {
      throw const PosTransientFailure("Couldn't load the print queue.");
    }
  }

  /// Take work off the queue.
  ///
  /// `claim_print_jobs` uses `for update skip locked`, which is what stops the
  /// till, the agent and three phones printing the same ticket: whoever locks
  /// the row first owns it, everyone else steps over it.
  ///
  /// [connections] and [renderModes] say what this device can actually drive.
  /// Claiming a job it cannot finish would take the ticket off the queue and
  /// produce no paper, which is worse than leaving it for something that can.
  Future<List<ClaimedPrintJob>> claim({
    required String claimer,
    required List<String> connections,
    required List<String> renderModes,
    String? branchId,
    int limit = 5,
  }) async {
    try {
      final rows = await _client.rpc<List<dynamic>>(
        'claim_print_jobs',
        params: {
          '_tenant': _tenantId,
          '_branch': branchId,
          '_claimer': claimer,
          '_limit': limit,
          '_connections': connections,
          '_render_modes': renderModes,
        },
      );
      return rows
          .whereType<Map<String, dynamic>>()
          .map(ClaimedPrintJob.fromJson)
          .toList();
    } on PostgrestException catch (e) {
      throw PosFailure(e.message);
    } catch (_) {
      throw const PosTransientFailure("Couldn't reach the print queue.");
    }
  }

  /// `printed` means paper came out. It is also what stamps `kots.printed_at`,
  /// so nothing else should claim it.
  Future<void> complete(String jobId, String status, [String? error]) => _write(
    'complete_print_job',
    {'_job_id': jobId, '_status': status, '_error': error},
    "Couldn't record that print.",
  );

  Future<void> retry(String jobId) =>
      _write('retry_print_job', {'_job_id': jobId}, "Couldn't retry that job.");

  /// Put a document on the queue by hand — a reprint, or the test page.
  ///
  /// Routing is resolved **here**, not in the RPC, exactly as the web's
  /// `enqueuePrint` does it: `enqueue_print_job` takes one printer and queues
  /// one job, so a document configured for two printers is two calls. Both
  /// clients therefore have to agree on how a printer is chosen, and the way to
  /// keep them agreeing is to port the rule rather than re-derive it.
  ///
  /// Everything the app queues by hand is a reprint, so `_idem` is always null:
  /// asking for a second copy of a ticket that already printed is the entire
  /// point of pressing the button.
  ///
  /// Permission is the server's: `enqueue_print_job` checks `order.view` for a
  /// ticket, `checkout.view` for a receipt and `settings.edit` for a test page.
  /// The UI hides what the key doesn't allow; the RPC is what enforces it.
  Future<EnqueueOutcome> enqueue({
    required String doc,
    String? kotId,
    String? billId,
    String? orderId,
    String? printerId,
  }) async {
    try {
      final resolved = await _resolveTargets(
        doc: doc,
        kotId: kotId,
        billId: billId,
        orderId: orderId,
        printerId: printerId,
      );
      if (resolved.targets.isEmpty) return const PrintNoPrinter();

      final jobIds = <String>[];
      for (final target in resolved.targets) {
        final id = await _client.rpc<dynamic>(
          'enqueue_print_job',
          params: {
            '_tenant': _tenantId,
            '_doc': resolved.doc,
            '_printer_id': target.printerId,
            '_kot_id': kotId,
            '_bill_id': billId,
            '_order_id': orderId,
            '_copies': target.copies,
            '_idem': null,
          },
        );
        if (id is String) jobIds.add(id);
      }
      return PrintQueued(jobIds);
    } on PostgrestException catch (e) {
      throw PosFailure(e.message);
    } on PosFailure {
      rethrow;
    } catch (_) {
      throw const PosTransientFailure("Couldn't reach the print queue.");
    }
  }

  /// Which printers this document is bound for, and what it is really called.
  ///
  /// The reads are here; the rules are in `print_routing.dart`, where they can
  /// be tested without a network.
  Future<({String doc, List<PrintTarget> targets})> _resolveTargets({
    required String doc,
    String? kotId,
    String? billId,
    String? orderId,
    String? printerId,
  }) async {
    var resolvedDoc = doc;
    String? branchId;
    var targets = <PrintTarget>[];

    if ((doc == 'kot' || doc == 'bot') && kotId != null) {
      final row = await _client
          .from('kots')
          .select('kitchen_stations(kind, printer_id), orders(branch_id)')
          .eq('id', kotId)
          .eq('tenant_id', _tenantId)
          .maybeSingle();

      final routing = kotRoutingFrom(row);
      resolvedDoc = routing.doc;
      branchId = routing.branchId;
      if (routing.station != null) targets = [routing.station!];
    } else {
      branchId = await _branchOf(billId: billId, orderId: orderId);
    }

    // "Print to this one" is an explicit instruction and outranks routing —
    // it is how the settings screen tests a single machine.
    if (printerId != null) {
      return (
        doc: resolvedDoc,
        targets: [PrintTarget(printerId: printerId, copies: 1)],
      );
    }
    if (targets.isNotEmpty) return (doc: resolvedDoc, targets: targets);

    final rows = await _client
        .from('printer_documents')
        .select('printer_id, copies, printers!inner(is_active, branch_id)')
        .eq('tenant_id', _tenantId)
        .eq('doc', resolvedDoc);

    return (
      doc: resolvedDoc,
      targets: printerDocumentTargets(rows, branchId: branchId),
    );
  }

  /// Which branch this document belongs to, so a printer tied to another one is
  /// skipped rather than printing a second branch's receipts.
  Future<String?> _branchOf({String? billId, String? orderId}) async {
    if (orderId != null) {
      final row = await _client
          .from('orders')
          .select('branch_id')
          .eq('id', orderId)
          .eq('tenant_id', _tenantId)
          .maybeSingle();
      return row?['branch_id'] as String?;
    }
    if (billId != null) {
      final row = await _client
          .from('bills')
          .select('branch_id')
          .eq('id', billId)
          .eq('tenant_id', _tenantId)
          .maybeSingle();
      return row?['branch_id'] as String?;
    }
    return null;
  }

  /// Every ticket an order fired, so "reprint the kitchen tickets" is one tap
  /// rather than a hunt through stations.
  Future<List<String>> orderKotIds(String orderId) async {
    try {
      final rows = await _client
          .from('kots')
          .select('id')
          .eq('tenant_id', _tenantId)
          .eq('order_id', orderId);
      return rows.map((r) => r['id'] as String?).nonNulls.toList();
    } on PostgrestException catch (e) {
      throw PosFailure(e.message);
    } catch (_) {
      throw const PosTransientFailure("Couldn't find the order's tickets.");
    }
  }

  /// The settings screen's "print a test page" — one printer, named outright,
  /// which is the whole point of testing *that* machine.
  Future<EnqueueOutcome> enqueueTest(String printerId) =>
      enqueue(doc: 'test', printerId: printerId);

  /// Server prose reaches the user rather than being swallowed. A reject and a
  /// timeout are different things — see `PLANNING.md` §2 rule 3.
  Future<void> _write(
    String fn,
    Map<String, dynamic> params,
    String transient,
  ) async {
    try {
      await _client.rpc<dynamic>(fn, params: params);
    } on PostgrestException catch (e) {
      throw PosFailure(e.message);
    } catch (_) {
      throw PosTransientFailure(transient);
    }
  }
}

final printRepositoryProvider = Provider.family<PrintRepository, String>(
  (ref, tenantId) => PrintRepository(ref.watch(supabaseProvider), tenantId),
);
