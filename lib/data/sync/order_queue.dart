import 'package:uuid/uuid.dart';

import '../../features/pos/models.dart';
import 'outbox.dart';
import 'replay_engine.dart';

/// What happened to a queued write by the time the caller got control back.
class QueueOutcome {
  const QueueOutcome({
    required this.entryId,
    required this.orderRef,
    required this.synced,
    this.error,
  });

  /// The outbox row this write became. The composer keeps it so it can ask
  /// later whether the dish it optimistically drew has actually landed.
  final int entryId;

  /// The server order id once the create landed; the local `draft:<uuid>`
  /// until then. Either way it identifies the order to the rest of the app.
  final String orderRef;

  /// True when the server has it. False means durable-but-owed, which is a
  /// success, not a failure — say so in those words.
  final bool synced;

  /// Set only when the server actively refused. Retrying will not help.
  final String? error;

  bool get isRejected => error != null;
}

/// The only way an order write leaves this app.
///
/// **Every write is enqueued first and attempted second** (rule 2), online
/// included. Writing straight to the server and queueing only when a *detected*
/// offline state is present loses the order in the window that matters most:
/// the socket throwing mid-call.
class OrderQueue {
  OrderQueue({
    required OutboxStore store,
    required ReplayEngine engine,
    required String tenantId,
    Uuid uuid = const Uuid(),
  }) : _store = store,
       _engine = engine,
       _tenantId = tenantId,
       _uuid = uuid;

  final OutboxStore _store;
  final ReplayEngine _engine;
  final String _tenantId;
  final Uuid _uuid;

  /// A local id for an order that has no server id yet.
  String newDraftRef() => 'draft:${_uuid.v4()}';

  static bool isDraftRef(String ref) => ref.startsWith('draft:');

  /// Queue a whole order. [idempotencyKey] is minted here if absent and then
  /// belongs to the row forever — a retry reuses it (rule 1).
  Future<QueueOutcome> placeOrder({
    required List<CartLine> lines,
    required String orderType,
    String? tableId,
    int? guests,
    bool fire = false,
    String? draftRef,
    String? idempotencyKey,
  }) async {
    final ref = draftRef ?? newDraftRef();
    final entry = await _store.enqueue(
      tenantId: _tenantId,
      kind: OutboxKind.order,
      orderRef: ref,
      idempotencyKey: idempotencyKey ?? _uuid.v4(),
      payload: {
        'order_type': orderType,
        'table_id': ?tableId,
        'guests': ?guests,
        'items': lines.map((l) => l.toRpcJson()).toList(),
        'fire': fire,
      },
    );
    return _drainAndReport(entry.id, ref);
  }

  /// Add a dish to an existing order.
  ///
  /// If that order is itself still queued, the dish is **merged into the
  /// pending create** rather than enqueued as its own op — there is no server
  /// id to amend yet, and two ops would race.
  Future<QueueOutcome> addItem({
    required String orderRef,
    required CartLine line,
  }) async {
    final pendingCreate = await _store.pendingCreateFor(orderRef);
    if (pendingCreate != null) {
      final items = List<Map<String, dynamic>>.from(
        (pendingCreate.payload['items'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>(),
      )..add(line.toRpcJson());
      await _store.updatePayload(pendingCreate.id, {
        ...pendingCreate.payload,
        'items': items,
      });
      return _drainAndReport(pendingCreate.id, orderRef);
    }

    final entry = await _store.enqueue(
      tenantId: _tenantId,
      kind: OutboxKind.amendAdd,
      orderRef: orderRef,
      idempotencyKey: _uuid.v4(),
      payload: line.toRpcJson(),
    );
    return _drainAndReport(entry.id, orderRef);
  }

  Future<QueueOutcome> voidLine({
    required String orderRef,
    required String orderItemId,
    required String reason,
  }) async {
    final entry = await _store.enqueue(
      tenantId: _tenantId,
      kind: OutboxKind.amendVoid,
      orderRef: orderRef,
      idempotencyKey: _uuid.v4(),
      payload: {'order_item_id': orderItemId, 'reason': reason},
    );
    return _drainAndReport(entry.id, orderRef);
  }

  /// Send to the kitchen. On an order that hasn't synced yet this flips the
  /// pending create's `fire` flag, so the create and the fire land together
  /// instead of the fire arriving for an order that doesn't exist.
  Future<QueueOutcome> fire(String orderRef) async {
    final pendingCreate = await _store.pendingCreateFor(orderRef);
    if (pendingCreate != null) {
      await _store.updatePayload(pendingCreate.id, {
        ...pendingCreate.payload,
        'fire': true,
      });
      return _drainAndReport(pendingCreate.id, orderRef);
    }

    final entry = await _store.enqueue(
      tenantId: _tenantId,
      kind: OutboxKind.fire,
      orderRef: orderRef,
      idempotencyKey: _uuid.v4(),
      payload: const {},
    );
    return _drainAndReport(entry.id, orderRef);
  }

  /// Mark a dish sold out, or put it back.
  ///
  /// Queued like an order: a waiter who 86s the last plate of momo while the
  /// wifi is down still needs that to reach the kitchen and the other phones.
  /// Replay is safe because this is last-write-wins on one row.
  Future<QueueOutcome> setItem86({
    required String itemId,
    required bool is86,
  }) async {
    final entry = await _store.enqueue(
      tenantId: _tenantId,
      kind: OutboxKind.menu86,
      orderRef: 'menu_item:$itemId',
      idempotencyKey: _uuid.v4(),
      payload: {'item_id': itemId, 'is_86': is86},
    );
    return _drainAndReport(entry.id, entry.orderRef);
  }

  Future<QueueOutcome> setTableState({
    required String tableId,
    required String state,
  }) async {
    final entry = await _store.enqueue(
      tenantId: _tenantId,
      kind: OutboxKind.tableState,
      orderRef: 'table:$tableId',
      idempotencyKey: _uuid.v4(),
      payload: {'table_id': tableId, 'state': state},
    );
    return _drainAndReport(entry.id, entry.orderRef);
  }

  /// Record a counted quantity for one line of a stock count.
  ///
  /// Counting a shelf twice is normal — someone miscounts, or finds another
  /// case behind the door. So a still-pending entry for the same line has its
  /// payload **replaced** rather than a second entry queued: the value is
  /// absolute, only the last one matters, and a queue of five edits to one line
  /// would show the store keeper five owed writes for one shelf.
  Future<QueueOutcome> setCountActual({
    required String countItemId,
    required double actual,
  }) => _lastWriteWins(
    kind: OutboxKind.stockCount,
    ref: 'count_item:$countItemId',
    payload: {'count_item_id': countItemId, 'actual': actual},
  );

  /// Move one dish on a kitchen ticket.
  ///
  /// Replaces a still-pending write for the same dish rather than queuing a
  /// second: a status is the absolute state of one row, so only the last tap
  /// matters — and a cook correcting a mis-tap should not owe the server two
  /// writes for one plate. Same reasoning as a re-counted shelf.
  Future<QueueOutcome> setKotLineStatus({
    required String kotItemId,
    required String status,
  }) => _lastWriteWins(
    kind: OutboxKind.kotLine,
    ref: 'kot_item:$kotItemId',
    payload: {'kot_item_id': kotItemId, 'status': status},
  );

  /// Move a whole kitchen ticket — including pulling a bumped one back, which
  /// is the `recalled` status rather than a verb of its own.
  Future<QueueOutcome> setKotStatus({
    required String kotId,
    required String status,
  }) => _lastWriteWins(
    kind: OutboxKind.kotTicket,
    ref: 'kot:$kotId',
    payload: {'kot_id': kotId, 'status': status},
  );

  /// The waiter delivered the order.
  ///
  /// Terminal and idempotent, so a replay writes the same state again. Queuing
  /// it means a waiter in a dead-signal corner of the room can still close the
  /// loop rather than holding the plate until the wifi agrees.
  Future<QueueOutcome> markOrderServed(String orderId) => _lastWriteWins(
    kind: OutboxKind.orderServed,
    ref: orderId,
    payload: const {},
  );

  /// Enqueue, or replace the payload of a pending write for the same row.
  Future<QueueOutcome> _lastWriteWins({
    required OutboxKind kind,
    required String ref,
    required Map<String, dynamic> payload,
  }) async {
    final pending = (await _store.due())
        .where(
          (e) =>
              e.kind == kind &&
              e.orderRef == ref &&
              e.state == OutboxState.pending,
        )
        .firstOrNull;
    if (pending != null) {
      await _store.updatePayload(pending.id, payload);
      return _drainAndReport(pending.id, ref);
    }

    final entry = await _store.enqueue(
      tenantId: _tenantId,
      kind: kind,
      orderRef: ref,
      idempotencyKey: _uuid.v4(),
      payload: payload,
    );
    return _drainAndReport(entry.id, ref);
  }

  /// Has the server finished with this row, one way or the other? A settled
  /// row is either on the server or given up on — in both cases the composer
  /// must stop drawing its own optimistic copy of the line.
  Future<bool> isSettled(int entryId) async {
    final row = await _store.byId(entryId);
    return row == null || !row.isDue;
  }

  /// Drop a queued write the waiter took back before it left. Only safe while
  /// the row is still `pending` — once it is inflight the server may already
  /// have it, and the honest path is a void with a reason.
  Future<bool> cancel(int entryId) async {
    final row = await _store.byId(entryId);
    if (row == null || row.state != OutboxState.pending) return false;
    await _store.discard(entryId);
    return true;
  }

  Future<int> pendingCount() => _store.pendingCount();

  Future<List<OutboxEntry>> deadEntries() => _store.deadEntries();

  Future<void> discard(int id) => _store.discard(id);

  /// Attempt now, then report what the row says. The row is the truth: it
  /// carries the server id once the create landed, and the reason when the
  /// server refused.
  Future<QueueOutcome> _drainAndReport(int entryId, String fallbackRef) async {
    await _engine.run();
    final row = await _store.byId(entryId);
    if (row == null) {
      return QueueOutcome(
        entryId: entryId,
        orderRef: fallbackRef,
        synced: true,
      );
    }
    return QueueOutcome(
      entryId: row.id,
      orderRef: row.orderRef,
      synced: row.state == OutboxState.done,
      error: row.state == OutboxState.dead
          ? (row.lastError ?? "The server refused it and didn't say why.")
          : null,
    );
  }
}
