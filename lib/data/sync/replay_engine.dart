import 'outbox.dart';
import 'transport.dart';

/// Drains the outbox.
///
/// Pure Dart on purpose — it depends on an [OutboxStore] and an
/// [OutboxTransport] and never on a widget, so every rule below is unit-tested
/// with no emulator (`PLANNING.md` §2, "Layers").
///
/// The five rules it enforces:
///
/// 1. The idempotency key travels with the entry and is reused on every retry.
/// 2. Enqueue happens before the attempt — that is the queue's job, not this
///    one's; the engine only ever replays what is already durable.
/// 3. Rejected → `dead` at once with the reason kept. Transient → `attempts++`
///    and retry, capped at [maxAttempts].
/// 4. `inflight` is persisted before the call, so a kill mid-call is
///    re-attempted rather than lost.
/// 5. Replay is **serial and in enqueue order**, and connectivity is re-checked
///    between entries — an amend must never land before its create.
class ReplayEngine {
  ReplayEngine({
    required OutboxStore store,
    required OutboxTransport transport,
    required Future<bool> Function() isOnline,
    this.maxAttempts = 5,
  }) : _store = store,
       _transport = transport,
       _isOnline = isOnline;

  final OutboxStore _store;
  final OutboxTransport _transport;
  final Future<bool> Function() _isOnline;
  final int maxAttempts;

  bool _running = false;

  /// True while a drain is in progress. Two concurrent drains would race the
  /// same rows into two attempts.
  bool get isRunning => _running;

  /// Attempt everything owed. Returns the number of entries that completed.
  ///
  /// Safe to call often — on connectivity change, on foreground, after every
  /// enqueue.
  Future<int> run() async {
    if (_running) return 0;
    _running = true;
    try {
      var completed = 0;

      // An order whose create died can never be amended. Its followers are
      // failed with a reason rather than thrown at the server to be rejected
      // one by one.
      final orphaned = <String>{};

      for (final queued in await _store.due()) {
        if (!await _isOnline()) break;

        // Re-read: an earlier entry in this same run may have remapped the
        // order ref from the local draft id to the real one.
        final entry = await _store.byId(queued.id) ?? queued;
        if (!entry.isDue) continue;

        if (orphaned.contains(entry.orderRef)) {
          await _store.markDead(
            entry.id,
            "The order this belongs to never reached the server, so this couldn't be sent either.",
          );
          continue;
        }

        await _store.markInflight(entry.id);

        try {
          await _dispatch(entry);
          await _store.markDone(entry.id);
          completed++;
        } on TransportRejected catch (e) {
          await _store.markDead(entry.id, e.message);
          if (entry.kind == OutboxKind.order) orphaned.add(entry.orderRef);
        } on TransportTransient catch (e) {
          final attempts = entry.attempts + 1;
          if (attempts >= maxAttempts) {
            await _store.markDead(entry.id, e.message);
            if (entry.kind == OutboxKind.order) orphaned.add(entry.orderRef);
          } else {
            await _store.reschedule(entry.id, e.message);
            // The network just failed. Hammering the rest of the queue would
            // burn every entry's retry cap on one outage.
            break;
          }
        }
      }
      return completed;
    } finally {
      _running = false;
    }
  }

  Future<void> _dispatch(OutboxEntry entry) async {
    switch (entry.kind) {
      case OutboxKind.order:
        final serverId = await _transport.placeOrder(
          idempotencyKey: entry.idempotencyKey,
          payload: entry.payload,
        );
        // Everything queued behind this create was addressed to the local
        // draft id. Rewrite them now, durably, so a crash before the next
        // entry doesn't lose the mapping.
        if (serverId != entry.orderRef) {
          await _store.remapOrderRef(entry.orderRef, serverId);
        }
        if (entry.payload['fire'] == true) {
          await _transport.fire(serverId);
        }
      case OutboxKind.amendAdd:
        await _transport.addItem(
          orderId: entry.orderRef,
          payload: entry.payload,
        );
      case OutboxKind.amendVoid:
        await _transport.voidLine(
          orderItemId: entry.payload['order_item_id'] as String,
          reason: (entry.payload['reason'] as String?) ?? '',
        );
      case OutboxKind.fire:
        await _transport.fire(entry.orderRef);
    }
  }
}
