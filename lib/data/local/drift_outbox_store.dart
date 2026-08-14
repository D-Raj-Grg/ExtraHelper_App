import 'package:drift/drift.dart';

import '../sync/outbox.dart';
import 'database.dart';

/// The outbox, on disk.
///
/// The only reason this exists rather than a memory queue: rule 4. An app
/// killed mid-call must find the row again on restart, still `inflight`, and
/// re-attempt it under the same key.
class DriftOutboxStore implements OutboxStore {
  DriftOutboxStore(this._db);

  final AppDatabase _db;

  OutboxEntry _toEntry(OutboxRow r) => OutboxEntry(
    id: r.id,
    tenantId: r.tenantId,
    kind: OutboxKind.values.byName(r.kind),
    orderRef: r.orderRef,
    payload: OutboxEntry.decodePayload(r.payloadJson),
    idempotencyKey: r.idempotencyKey,
    attempts: r.attempts,
    state: OutboxState.values.byName(r.state),
    createdAt: r.createdAt,
    lastError: r.lastError,
  );

  @override
  Future<OutboxEntry> enqueue({
    required String tenantId,
    required OutboxKind kind,
    required String orderRef,
    required Map<String, dynamic> payload,
    required String idempotencyKey,
  }) {
    // In one transaction, so two taps racing the same key can't both insert.
    return _db.transaction(() async {
      final existing =
          await (_db.select(_db.outboxRows)
                ..where((t) => t.idempotencyKey.equals(idempotencyKey)))
              .getSingleOrNull();
      if (existing != null) return _toEntry(existing);

      final id = await _db
          .into(_db.outboxRows)
          .insert(
            OutboxRowsCompanion.insert(
              tenantId: tenantId,
              kind: kind.name,
              orderRef: orderRef,
              payloadJson: OutboxEntry(
                id: 0,
                tenantId: tenantId,
                kind: kind,
                orderRef: orderRef,
                payload: payload,
                idempotencyKey: idempotencyKey,
                attempts: 0,
                state: OutboxState.pending,
                createdAt: DateTime.now(),
              ).payloadJson,
              idempotencyKey: idempotencyKey,
              state: OutboxState.pending.name,
              createdAt: DateTime.now(),
            ),
          );
      final row = await (_db.select(
        _db.outboxRows,
      )..where((t) => t.id.equals(id))).getSingle();
      return _toEntry(row);
    });
  }

  @override
  Future<List<OutboxEntry>> due() async {
    final rows =
        await (_db.select(_db.outboxRows)
              ..where(
                (t) => t.state.isIn([
                  OutboxState.pending.name,
                  OutboxState.inflight.name,
                ]),
              )
              ..orderBy([(t) => OrderingTerm.asc(t.id)]))
            .get();
    return rows.map(_toEntry).toList();
  }

  @override
  Future<List<OutboxEntry>> all() async {
    final rows = await (_db.select(
      _db.outboxRows,
    )..orderBy([(t) => OrderingTerm.asc(t.id)])).get();
    return rows.map(_toEntry).toList();
  }

  @override
  Future<OutboxEntry?> byId(int id) async {
    final row = await (_db.select(
      _db.outboxRows,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _toEntry(row);
  }

  Future<void> _update(int id, OutboxRowsCompanion values) =>
      (_db.update(_db.outboxRows)..where((t) => t.id.equals(id))).write(values);

  /// Persisted **before** the call goes out, in its own transaction, so a kill
  /// mid-call leaves evidence rather than a gap.
  @override
  Future<void> markInflight(int id) => _db.transaction(
    () => _update(
      id,
      OutboxRowsCompanion(state: Value(OutboxState.inflight.name)),
    ),
  );

  @override
  Future<void> markDone(int id) =>
      _update(id, OutboxRowsCompanion(state: Value(OutboxState.done.name)));

  @override
  Future<void> markDead(int id, String error) => _update(
    id,
    OutboxRowsCompanion(
      state: Value(OutboxState.dead.name),
      lastError: Value(error),
    ),
  );

  @override
  Future<void> reschedule(int id, String error) async {
    final row = await byId(id);
    if (row == null) return;
    await _update(
      id,
      OutboxRowsCompanion(
        state: Value(OutboxState.pending.name),
        attempts: Value(row.attempts + 1),
        lastError: Value(error),
      ),
    );
  }

  @override
  Future<void> remapOrderRef(String from, String to) =>
      (_db.update(_db.outboxRows)..where((t) => t.orderRef.equals(from))).write(
        OutboxRowsCompanion(orderRef: Value(to)),
      );

  @override
  Future<OutboxEntry?> pendingCreateFor(String orderRef) async {
    final row =
        await (_db.select(_db.outboxRows)
              ..where(
                (t) =>
                    t.orderRef.equals(orderRef) &
                    t.kind.equals(OutboxKind.order.name) &
                    t.state.equals(OutboxState.pending.name),
              )
              ..limit(1))
            .getSingleOrNull();
    return row == null ? null : _toEntry(row);
  }

  @override
  Future<void> updatePayload(int id, Map<String, dynamic> payload) async {
    final row = await byId(id);
    if (row == null) return;
    await _update(
      id,
      OutboxRowsCompanion(
        payloadJson: Value(row.copyWith(payload: payload).payloadJson),
      ),
    );
  }

  @override
  Future<int> pendingCount() async => (await due()).length;

  @override
  Future<List<OutboxEntry>> deadEntries() async {
    final rows =
        await (_db.select(_db.outboxRows)
              ..where((t) => t.state.equals(OutboxState.dead.name))
              ..orderBy([(t) => OrderingTerm.asc(t.id)]))
            .get();
    return rows.map(_toEntry).toList();
  }

  @override
  Future<void> discard(int id) =>
      (_db.delete(_db.outboxRows)..where((t) => t.id.equals(id))).go();

  @override
  Future<int> pruneSettled(DateTime before) =>
      (_db.delete(_db.outboxRows)..where(
            (t) =>
                t.state.equals(OutboxState.done.name) &
                t.createdAt.isSmallerThanValue(before),
          ))
          .go();
}
