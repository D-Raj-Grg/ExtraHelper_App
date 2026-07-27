import 'dart:convert';

/// What a queued write does.
///
/// `fire` is a fourth kind beyond the three `PLANNING.md` §2 names. Sending to
/// the kitchen is a separate, separately-idempotent RPC (`fire_order`), and an
/// offline session is normally *N* adds followed by one fire — folding it into
/// another entry's payload would either fire too early or lose the fire when
/// there was nothing new to add.
enum OutboxKind { order, amendAdd, amendVoid, fire }

/// `inflight` is a **persisted** state, not a memory flag (rule 4). A process
/// killed mid-call leaves the row `inflight`; the next run re-attempts it under
/// the same idempotency key, which is safe precisely because of rule 1.
enum OutboxState { pending, inflight, done, dead }

/// One durable write.
class OutboxEntry {
  const OutboxEntry({
    required this.id,
    required this.tenantId,
    required this.kind,
    required this.orderRef,
    required this.payload,
    required this.idempotencyKey,
    required this.attempts,
    required this.state,
    required this.createdAt,
    this.lastError,
  });

  final int id;
  final String tenantId;
  final OutboxKind kind;

  /// The order this entry belongs to: a local `draft:<uuid>` until the create
  /// lands, then rewritten to the server id. Replay is serial per order, so
  /// this is also the grouping key.
  final String orderRef;

  final Map<String, dynamic> payload;

  /// Minted at enqueue, **never regenerated** (rule 1).
  final String idempotencyKey;

  final int attempts;
  final OutboxState state;
  final DateTime createdAt;
  final String? lastError;

  bool get isDue =>
      state == OutboxState.pending || state == OutboxState.inflight;

  OutboxEntry copyWith({
    OutboxKind? kind,
    String? orderRef,
    Map<String, dynamic>? payload,
    int? attempts,
    OutboxState? state,
    String? lastError,
  }) => OutboxEntry(
    id: id,
    tenantId: tenantId,
    kind: kind ?? this.kind,
    orderRef: orderRef ?? this.orderRef,
    payload: payload ?? this.payload,
    idempotencyKey: idempotencyKey,
    attempts: attempts ?? this.attempts,
    state: state ?? this.state,
    createdAt: createdAt,
    lastError: lastError ?? this.lastError,
  );

  String get payloadJson => jsonEncode(payload);

  static Map<String, dynamic> decodePayload(String json) =>
      jsonDecode(json) as Map<String, dynamic>;
}

/// Durable storage for queued writes.
///
/// Deliberately an interface: the replay engine is pure Dart and unit-tested
/// against [MemoryOutboxStore] with no sqlite, no emulator, no widgets.
abstract class OutboxStore {
  /// Enqueue, or return the existing row when [idempotencyKey] was already
  /// queued. **Double-enqueue must never produce two rows** — that is how one
  /// tap becomes two orders.
  Future<OutboxEntry> enqueue({
    required String tenantId,
    required OutboxKind kind,
    required String orderRef,
    required Map<String, dynamic> payload,
    required String idempotencyKey,
  });

  /// Everything still owed to the server, oldest first. Includes `inflight` —
  /// see [OutboxState].
  Future<List<OutboxEntry>> due();

  Future<List<OutboxEntry>> all();

  Future<OutboxEntry?> byId(int id);

  Future<void> markInflight(int id);

  Future<void> markDone(int id);

  Future<void> markDead(int id, String error);

  /// Transient failure: count the attempt and go back to `pending`.
  Future<void> reschedule(int id, String error);

  /// The create landed — every queued entry that still points at the local
  /// draft id now points at the real order.
  Future<void> remapOrderRef(String from, String to);

  /// The pending create for [orderRef], if it hasn't been sent yet. An amend
  /// against a not-yet-synced order merges into this rather than queuing an op
  /// the server could never resolve.
  Future<OutboxEntry?> pendingCreateFor(String orderRef);

  Future<void> updatePayload(int id, Map<String, dynamic> payload);

  /// Writes still owed. Drives the app-bar badge.
  Future<int> pendingCount();

  Future<List<OutboxEntry>> deadEntries();

  /// Acknowledge a dead entry — the waiter has seen the failure.
  Future<void> discard(int id);

  /// Drop `done` rows older than [keep]. They are receipts, not work, and a
  /// phone that lives on a service floor for a year would otherwise carry every
  /// order it ever sent. `dead` rows are never pruned — someone still has to
  /// see them.
  Future<int> pruneSettled(DateTime before);
}

/// In-memory store. Used by the unit tests, and by nothing else.
class MemoryOutboxStore implements OutboxStore {
  final List<OutboxEntry> _rows = [];
  int _nextId = 1;

  @override
  Future<OutboxEntry> enqueue({
    required String tenantId,
    required OutboxKind kind,
    required String orderRef,
    required Map<String, dynamic> payload,
    required String idempotencyKey,
  }) async {
    final existing = _rows
        .where((r) => r.idempotencyKey == idempotencyKey)
        .firstOrNull;
    if (existing != null) return existing;

    final entry = OutboxEntry(
      id: _nextId++,
      tenantId: tenantId,
      kind: kind,
      orderRef: orderRef,
      payload: payload,
      idempotencyKey: idempotencyKey,
      attempts: 0,
      state: OutboxState.pending,
      createdAt: DateTime.fromMillisecondsSinceEpoch(_nextId),
    );
    _rows.add(entry);
    return entry;
  }

  @override
  Future<List<OutboxEntry>> due() async =>
      _rows.where((r) => r.isDue).toList()
        ..sort((a, b) => a.id.compareTo(b.id));

  @override
  Future<List<OutboxEntry>> all() async => List.unmodifiable(_rows);

  @override
  Future<OutboxEntry?> byId(int id) async =>
      _rows.where((r) => r.id == id).firstOrNull;

  void _replace(int id, OutboxEntry Function(OutboxEntry) f) {
    final i = _rows.indexWhere((r) => r.id == id);
    if (i >= 0) _rows[i] = f(_rows[i]);
  }

  @override
  Future<void> markInflight(int id) async =>
      _replace(id, (e) => e.copyWith(state: OutboxState.inflight));

  @override
  Future<void> markDone(int id) async =>
      _replace(id, (e) => e.copyWith(state: OutboxState.done));

  @override
  Future<void> markDead(int id, String error) async => _replace(
    id,
    (e) => e.copyWith(state: OutboxState.dead, lastError: error),
  );

  @override
  Future<void> reschedule(int id, String error) async => _replace(
    id,
    (e) => e.copyWith(
      state: OutboxState.pending,
      attempts: e.attempts + 1,
      lastError: error,
    ),
  );

  @override
  Future<void> remapOrderRef(String from, String to) async {
    for (var i = 0; i < _rows.length; i++) {
      if (_rows[i].orderRef == from) _rows[i] = _rows[i].copyWith(orderRef: to);
    }
  }

  @override
  Future<OutboxEntry?> pendingCreateFor(String orderRef) async => _rows
      .where(
        (r) =>
            r.orderRef == orderRef &&
            r.kind == OutboxKind.order &&
            r.state == OutboxState.pending,
      )
      .firstOrNull;

  @override
  Future<void> updatePayload(int id, Map<String, dynamic> payload) async =>
      _replace(id, (e) => e.copyWith(payload: payload));

  @override
  Future<int> pendingCount() async => _rows.where((r) => r.isDue).length;

  @override
  Future<List<OutboxEntry>> deadEntries() async =>
      _rows.where((r) => r.state == OutboxState.dead).toList();

  @override
  Future<void> discard(int id) async => _rows.removeWhere((r) => r.id == id);

  @override
  Future<int> pruneSettled(DateTime before) async {
    final before0 = _rows.length;
    _rows.removeWhere(
      (r) => r.state == OutboxState.done && r.createdAt.isBefore(before),
    );
    return before0 - _rows.length;
  }
}
