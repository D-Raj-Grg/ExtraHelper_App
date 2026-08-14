import 'package:uuid/uuid.dart';

import '../../data/supabase/pos_repository.dart';
import '../../data/sync/order_queue.dart';
import 'models.dart';

/// What a cart can do, as **capabilities rather than a mode flag**.
///
/// The composer asks "can I delete this line?" and "does committing do
/// anything?", never "am I in create mode or amend mode?". This is the pattern
/// the web settled on (`components/pos/cart-types.ts`): one screen, two
/// behaviours, and only the controllers know they differ.
///
/// The difference is real, not cosmetic:
///
/// * **Create** batches locally and commits as ONE queued `place_staff_order`.
/// * **Amend** sends each edit as its own queued op, because a line on a
///   kitchen ticket needs a reasoned, audited void — not a silent local edit.
///
/// What they now share: **nothing writes to the server directly.** Every write
/// is enqueued in the outbox and attempted from there (rule 2), online
/// included, so a socket that throws mid-call has already left a durable row
/// under an idempotency key that cannot duplicate the order.
abstract class CartController {
  /// Lines as the waiter sees them, whether local, queued or already fired.
  List<CartDisplayLine> get lines;

  int get totalCents;

  int get itemCount;

  /// Adding is always allowed while the order is open; the server has the
  /// final say on 86'd dishes.
  Future<void> add(CartLine line);

  /// Some lines can be removed outright; a fired one needs a reasoned void.
  bool canDelete(String lineId);

  /// True when removing this line requires a reason (it's on a kitchen ticket).
  bool needsVoidReason(String lineId);

  Future<void> remove(String lineId, {String? reason});

  Future<void> setQty(String lineId, int qty);

  /// Queue the order (create) or the fire (amend), and report whether the
  /// server already has it.
  Future<CartCommit> commit({required bool fire});

  /// Whether [commit] still has work to do (drives the button's wording).
  bool get hasPendingCommit;
}

/// The result of committing: which order, and whether the server has it yet.
class CartCommit {
  const CartCommit({required this.orderRef, required this.synced});

  final String orderRef;

  /// False means durable-but-owed. That is a success — the outbox will land it
  /// — and the wording the waiter sees must say so, not apologise.
  final bool synced;
}

/// One row in the cart, from any source.
class CartDisplayLine {
  const CartDisplayLine({
    required this.id,
    required this.title,
    required this.qty,
    required this.unitPriceCents,
    required this.canEditQty,
    required this.isFired,
    this.isPending = false,
    this.notes,
    this.modifierNames = const [],
  });

  final String id;
  final String title;
  final int qty;
  final int unitPriceCents;
  final bool canEditQty;
  final bool isFired;

  /// Queued but not yet acknowledged by the server. Shown, because a waiter who
  /// added a dish must see it on the order whatever the wifi is doing.
  final bool isPending;

  final String? notes;
  final List<String> modifierNames;

  int get lineTotalCents => unitPriceCents * qty;
}

/// Composing a new order. Everything is local until [commit].
class CreateCart implements CartController {
  CreateCart({
    required OrderQueue queue,
    required this.orderType,
    this.tableId,
    this.guests,
  }) : _queue = queue,
       draftRef = queue.newDraftRef();

  final OrderQueue _queue;
  final String orderType;
  final String? tableId;

  /// How many people are eating. Mutable because the waiter is told it at the
  /// table, often after the first dish has been chosen — and it travels to
  /// `place_staff_order` in the same call as the lines, so it only has to be
  /// right at commit.
  int? guests;

  /// This order's identity before the server has one. Held from the start so a
  /// retry, or an amend made before the create lands, addresses the same order.
  final String draftRef;

  final List<CartLine> _lines = [];
  static const _uuid = Uuid();

  /// Minted once and **reused for every retry**. A fresh key per attempt is how
  /// you get two orders from one tap.
  String? _idempotencyKey;

  List<CartLine> get rawLines => List.unmodifiable(_lines);

  @override
  List<CartDisplayLine> get lines => _lines
      .map(
        (l) => CartDisplayLine(
          id: l.localId,
          title: l.title,
          qty: l.qty,
          unitPriceCents: l.unitPriceCents,
          canEditQty: true,
          isFired: false,
          notes: l.notes,
          modifierNames: l.modifiers.map((m) => m.name).toList(),
        ),
      )
      .toList();

  @override
  int get totalCents => _lines.fold(0, (s, l) => s + l.lineTotalCents);

  @override
  int get itemCount => _lines.fold(0, (s, l) => s + l.qty);

  @override
  Future<void> add(CartLine line) async {
    // Merge identical lines rather than stacking duplicates — the signature
    // decides sameness; the stable localId stays the row's key.
    final i = _lines.indexWhere((l) => l.signature == line.signature);
    if (i >= 0) {
      _lines[i] = _lines[i].copyWith(qty: _lines[i].qty + line.qty);
    } else {
      _lines.add(line);
    }
  }

  @override
  bool canDelete(String lineId) => true;

  @override
  bool needsVoidReason(String lineId) => false;

  @override
  Future<void> remove(String lineId, {String? reason}) async {
    _lines.removeWhere((l) => l.localId == lineId);
  }

  @override
  Future<void> setQty(String lineId, int qty) async {
    final i = _lines.indexWhere((l) => l.localId == lineId);
    if (i < 0) return;
    if (qty <= 0) {
      _lines.removeAt(i);
      return;
    }
    _lines[i] = _lines[i].copyWith(qty: qty.clamp(1, 99));
  }

  @override
  bool get hasPendingCommit => _lines.isNotEmpty;

  @override
  Future<CartCommit> commit({required bool fire}) async {
    if (_lines.isEmpty) throw const PosFailure('Add something first.');
    _idempotencyKey ??= _uuid.v4();

    final outcome = await _queue.placeOrder(
      lines: _lines,
      orderType: orderType,
      tableId: tableId,
      guests: guests,
      fire: fire,
      draftRef: draftRef,
      idempotencyKey: _idempotencyKey,
    );
    if (outcome.isRejected) throw PosFailure(outcome.error!);
    return CartCommit(orderRef: outcome.orderRef, synced: outcome.synced);
  }
}

/// Editing an order that already exists. Every change is a queued server op.
class AmendCart implements CartController {
  AmendCart({
    required OrderQueue queue,
    required PosRepository repository,
    required PosOrder order,
  }) : _queue = queue,
       _repo = repository,
       _order = order;

  final OrderQueue _queue;

  /// Quantity and draft-line edits are not money-critical writes: the line is
  /// not on a ticket yet, and there is nothing to replay if it fails. They stay
  /// direct calls rather than earning an outbox row that could never be merged.
  final PosRepository _repo;

  PosOrder _order;

  /// Dishes added but not yet acknowledged. They appear on the order because
  /// the waiter added them; they are not editable, because the server hasn't
  /// agreed yet and there is no line id to edit.
  final List<({int entryId, CartLine line})> _pending = [];

  PosOrder get order => _order;

  /// Replace the snapshot after a refetch, so the cart shows server truth
  /// rather than a frozen copy.
  void update(PosOrder order) => _order = order;

  /// Drop the queued adds the server has now accepted (or given up on) — they
  /// are in [_order] as real lines, and showing both would double the order.
  Future<void> reconcilePending() async {
    if (_pending.isEmpty) return;
    final settled = <int>[];
    for (final p in _pending) {
      if (await _queue.isSettled(p.entryId)) settled.add(p.entryId);
    }
    _pending.removeWhere((p) => settled.contains(p.entryId));
  }

  List<PosOrderLine> get _live => _order.lines.where((l) => !l.isVoid).toList();

  @override
  List<CartDisplayLine> get lines => [
    ..._live.map(
      (l) => CartDisplayLine(
        id: l.id,
        title: l.nameSnapshot,
        qty: l.qty,
        unitPriceCents: l.unitPriceCents,
        canEditQty: !l.isFired,
        isFired: l.isFired,
        notes: l.notes,
        modifierNames: l.modifierNames,
      ),
    ),
    ..._pending.map(
      (p) => CartDisplayLine(
        id: p.line.localId,
        title: p.line.title,
        qty: p.line.qty,
        unitPriceCents: p.line.unitPriceCents,
        canEditQty: false,
        isFired: false,
        isPending: true,
        notes: p.line.notes,
        modifierNames: p.line.modifiers.map((m) => m.name).toList(),
      ),
    ),
  ];

  @override
  int get totalCents =>
      _order.totalCents + _pending.fold(0, (s, p) => s + p.line.lineTotalCents);

  @override
  int get itemCount =>
      _order.itemCount + _pending.fold(0, (s, p) => s + p.line.qty);

  @override
  Future<void> add(CartLine line) async {
    final outcome = await _queue.addItem(orderRef: _order.id, line: line);
    if (outcome.isRejected) throw PosFailure(outcome.error!);
    if (!outcome.synced) {
      _pending.add((entryId: outcome.entryId, line: line));
    }
  }

  @override
  bool canDelete(String lineId) => true;

  @override
  bool needsVoidReason(String lineId) {
    final line = _live.where((l) => l.id == lineId).firstOrNull;
    return line?.isFired ?? false;
  }

  @override
  Future<void> remove(String lineId, {String? reason}) async {
    // A queued add that hasn't landed: nothing to void, just drop it. Cancelling
    // the outbox entry is safer than voiding a line id that doesn't exist yet.
    final queued = _pending.where((p) => p.line.localId == lineId).firstOrNull;
    if (queued != null) {
      await _queue.cancel(queued.entryId);
      _pending.removeWhere((p) => p.entryId == queued.entryId);
      return;
    }

    if (needsVoidReason(lineId)) {
      final outcome = await _queue.voidLine(
        orderRef: _order.id,
        orderItemId: lineId,
        reason: reason ?? '',
      );
      if (outcome.isRejected) throw PosFailure(outcome.error!);
      return;
    }
    await _repo.deleteDraftLine(lineId);
  }

  @override
  Future<void> setQty(String lineId, int qty) =>
      _repo.setLineQty(lineId: lineId, qty: qty);

  /// Nothing is pending on the *create*: this order exists. Committing an amend
  /// means firing what was added.
  @override
  bool get hasPendingCommit => false;

  @override
  Future<CartCommit> commit({required bool fire}) async {
    if (!fire) return CartCommit(orderRef: _order.id, synced: true);
    final outcome = await _queue.fire(_order.id);
    if (outcome.isRejected) throw PosFailure(outcome.error!);
    return CartCommit(orderRef: outcome.orderRef, synced: outcome.synced);
  }
}
