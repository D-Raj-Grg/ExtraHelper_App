import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/pos_repository.dart' show PosFailure, PosTransientFailure;
import '../supabase/supabase_providers.dart';
import 'print_models.dart';

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

  /// Put a document on the queue by hand — the test page, or a reprint.
  ///
  /// A test page carries no idempotency key: asking for a second one is the
  /// whole point of pressing the button twice.
  Future<String?> enqueueTest(String printerId) async {
    try {
      final id = await _client.rpc<dynamic>(
        'enqueue_print_job',
        params: {
          '_tenant': _tenantId,
          '_doc': 'test',
          '_printer_id': printerId,
          '_kot_id': null,
          '_bill_id': null,
          '_order_id': null,
          '_copies': 1,
          '_idem': null,
        },
      );
      return id as String?;
    } on PostgrestException catch (e) {
      throw PosFailure(e.message);
    } catch (_) {
      throw const PosTransientFailure("Couldn't queue the test page.");
    }
  }

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
