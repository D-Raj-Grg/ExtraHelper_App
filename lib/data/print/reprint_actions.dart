/// The one way the app asks for a second copy of something.
///
/// Nothing prints from here. Each of these queues the document and returns the
/// sentence to show — whichever device is set up to drive that printer takes
/// the job off the queue, which is what makes a ticket come out exactly once no
/// matter how many phones asked.
///
/// **Deliberately not gated on `Env.canPrint` / `printEnabledProvider`.** Those
/// say whether *this* device drains the queue. A waiter's phone with no printer
/// attached is exactly the device that needs to ask the counter's printer for a
/// receipt, and gating enqueue would take that away.
///
/// **Deliberately not queued through the outbox.** A reprint asked for ten
/// minutes ago is not a reprint anyone still wants, and the queue's ordering
/// guarantees are per-order. Offline says so and stops.
///
/// Takes a `WidgetRef` rather than a `Ref`: every caller is a button someone
/// pressed, and the answer is a sentence to put in front of them.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/tenant/tenant_providers.dart';
import '../supabase/pos_repository.dart' show PosFailure;
import '../sync/sync_providers.dart';
import 'print_models.dart';
import 'print_repository.dart';

const _offlineMessage =
    'No coverage — a reprint needs a connection. Try again when '
    "you're back.";

const _noPrinterMessage =
    'No printer is set up for this yet. Add one on the web app under '
    'Settings → Printers.';

/// A receipt, again. Needs `checkout.view`; the RPC enforces it.
Future<String> reprintBill(WidgetRef ref, String billId) => _enqueue(
  ref,
  doc: 'bill',
  billId: billId,
  queued: 'Receipt sent to print.',
);

/// The order slip — the waiter's copy, not the kitchen's. Needs `order.view`.
Future<String> reprintOrderSlip(WidgetRef ref, String orderId) => _enqueue(
  ref,
  doc: 'order_slip',
  orderId: orderId,
  queued: 'Order slip sent to print.',
);

/// One kitchen ticket. The station decides whether it comes out as a KOT or a
/// BOT, so a bar ticket reprinted from the pass still reads as a bar ticket.
Future<String> reprintKot(WidgetRef ref, String kotId) =>
    _enqueue(ref, doc: 'kot', kotId: kotId, queued: 'Ticket sent to print.');

/// Every ticket an order fired, one job per station.
///
/// Reported as a count rather than per-station: a waiter asking for "the
/// kitchen tickets" wants to know they all went, not which printer got which.
Future<String> reprintOrderKots(WidgetRef ref, String orderId) async {
  final repo = _repo(ref);
  if (repo == null) return 'No restaurant selected.';
  if (!await ref.read(connectivityProvider).isOnline()) return _offlineMessage;

  try {
    final kotIds = await repo.orderKotIds(orderId);
    if (kotIds.isEmpty) {
      return 'That order has no kitchen tickets — nothing was fired yet.';
    }

    var queued = 0;
    for (final kotId in kotIds) {
      final outcome = await repo.enqueue(doc: 'kot', kotId: kotId);
      // An empty `jobIds` is not a queued ticket — `enqueue_print_job` can
      // return null, and `_enqueue` already calls that case a failure. Counting
      // it here would tell a waiter "3 tickets sent to print" over a printer
      // that received nothing.
      if (outcome is PrintQueued && outcome.jobIds.isNotEmpty) queued++;
    }
    if (queued == 0) return _noPrinterMessage;
    return queued == 1
        ? 'Ticket sent to print.'
        : '$queued tickets sent to print.';
  } on PosFailure catch (e) {
    // Covers PosTransientFailure too — both carry a sentence meant for the
    // person holding the phone.
    return e.message;
  }
}

Future<String> _enqueue(
  WidgetRef ref, {
  required String doc,
  required String queued,
  String? kotId,
  String? billId,
  String? orderId,
}) async {
  final repo = _repo(ref);
  if (repo == null) return 'No restaurant selected.';
  if (!await ref.read(connectivityProvider).isOnline()) return _offlineMessage;

  try {
    final outcome = await repo.enqueue(
      doc: doc,
      kotId: kotId,
      billId: billId,
      orderId: orderId,
    );
    return switch (outcome) {
      PrintQueued(:final jobIds) when jobIds.isNotEmpty => queued,
      PrintQueued() => 'That document could not be queued.',
      PrintNoPrinter() => _noPrinterMessage,
    };
  } on PosFailure catch (e) {
    // Covers PosTransientFailure too — both carry a sentence meant for the
    // person holding the phone.
    return e.message;
  }
}

PrintRepository? _repo(WidgetRef ref) {
  final tenant = ref.read(activeTenantProvider);
  if (tenant == null) return null;
  return ref.read(printRepositoryProvider(tenant.tenantId));
}
