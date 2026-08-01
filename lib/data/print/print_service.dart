import 'dart:async';

import '../supabase/pos_repository.dart' show PosFailure;
import 'print_models.dart';
import 'print_repository.dart';
import 'render_client.dart';
import 'transports/print_transport.dart';

/// Drains the print queue on this device.
///
/// The shape is the headless agent's (`tools/print-agent/agent.mjs`), because
/// the queue was designed for exactly this: claim → render → send → complete.
/// What differs is only the wire and the wake-up.
///
/// Nothing here knows what a KOT looks like. That is the point — a phone, a
/// till and a shop PC all print the same bytes.
class PrintService {
  PrintService({
    required PrintRepository repository,
    required RenderClient renderClient,
    required List<PrintTransport> transports,
    required this.claimer,
    this.branchId,
  }) : _repo = repository,
       _render = renderClient,
       _transports = transports;

  final PrintRepository _repo;
  final RenderClient _render;
  final List<PrintTransport> _transports;

  /// Written to `print_jobs.claimed_by`, so "who printed this twice?" has an
  /// answer.
  final String claimer;
  final String? branchId;

  bool _draining = false;

  /// True while a drain is in flight. One at a time: a burst of station tickets
  /// arriving together must not start several overlapping claims fighting over
  /// the same rows.
  bool get isDraining => _draining;

  /// The last error worth showing on the printing screen. Cleared by a drain
  /// that gets through cleanly.
  String? lastError;

  /// Jobs put on paper since the app started — the printing screen uses it to
  /// prove the device is doing something.
  int printed = 0;

  /// Take everything currently queued that this device can drive.
  ///
  /// Returns how many jobs printed. Rounds are capped so a queue that keeps
  /// refilling cannot pin the loop forever; the next wake-up picks it up.
  Future<int> drain() async {
    if (_draining) return 0;
    _draining = true;
    var done = 0;
    try {
      final connections = <String>[];
      for (final t in _transports) {
        if (await t.available) {
          connections.add(printerConnectionWire(t.connection));
        }
      }
      // Nothing can print here right now — Bluetooth off and no transports
      // left. Claiming would strand tickets on a device that cannot finish them.
      if (connections.isEmpty) return 0;

      for (var round = 0; round < 5; round++) {
        final jobs = await _repo.claim(
          claimer: claimer,
          connections: connections,
          // Image mode is rasterised by a browser; this app has no rasteriser
          // yet, so those tickets stay for something that does.
          renderModes: const ['text'],
          branchId: branchId,
        );
        if (jobs.isEmpty) break;

        for (final job in jobs) {
          if (await _run(job)) done++;
        }
      }
      lastError = null;
      // `PosTransientFailure` is a `PosFailure`, so one clause covers both. The
      // difference matters to the outbox, not here: either way the queue keeps
      // the job and the next wake-up tries again.
    } on PosFailure catch (e) {
      lastError = e.message;
    } catch (e) {
      lastError = '$e';
    } finally {
      _draining = false;
    }
    printed += done;
    return done;
  }

  /// One job, from claimed to accounted for.
  ///
  /// Every exit path completes the job. A claimed row that is never completed
  /// only unsticks after the 60-second stale-claim sweep, which in a kitchen is
  /// a minute of nobody cooking.
  Future<bool> _run(ClaimedPrintJob job) async {
    PreparedPrintJob prepared;
    try {
      prepared = await _render.render(job.id);
    } catch (e) {
      await _fail(job.id, '$e');
      return false;
    }

    final printer = prepared.printer;
    if (printer == null) {
      await _fail(job.id, 'That job has no printer.');
      return false;
    }
    if (prepared.isImagePayload || prepared.base64 == null) {
      await _fail(
        job.id,
        '${printer.name} is set to image mode, which this app cannot draw yet — '
        'switch it to text, or print it from a computer running QZ Tray.',
      );
      return false;
    }

    final transport = _transportFor(printer.connection);
    if (transport == null) {
      await _fail(
        job.id,
        '${printer.name} is a ${printerConnectionLabel(printer.connection)} '
        'printer, which a phone cannot drive.',
      );
      return false;
    }

    final copies = prepared.copies.clamp(1, 5);
    try {
      for (var i = 0; i < copies; i++) {
        await transport.send(printer, prepared.base64!);
      }
    } catch (e) {
      // Out of paper, switched off, moved to another network. The job stays
      // visible and retryable rather than vanishing with a toast nobody saw.
      await _fail(job.id, e is PrintTransportFailure ? e.message : '$e');
      return false;
    }

    try {
      await _repo.complete(job.id, 'printed');
    } catch (_) {
      // The paper is already out. Losing the acknowledgement re-queues the job
      // after 60s and prints it twice, which is worth knowing about but not
      // worth failing the print for.
      lastError =
          'Printed ${prepared.label}, but could not tell the server. '
          'It may print again.';
    }
    return true;
  }

  PrintTransport? _transportFor(PrinterConnection connection) {
    for (final t in _transports) {
      if (t.connection == connection) return t;
    }
    return null;
  }

  Future<void> _fail(String jobId, String message) async {
    try {
      await _repo.complete(jobId, 'failed', message);
    } catch (_) {
      // Nothing more to do: the stale-claim sweep will re-queue it.
    }
    lastError = message;
  }
}
