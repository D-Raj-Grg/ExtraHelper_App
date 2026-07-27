import 'package:uuid/uuid.dart';

import '../../data/supabase/pos_repository.dart';
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
/// * **Create** batches locally and commits in ONE `place_staff_order` call —
///   atomic, and it carries a client-minted idempotency key so a retry can't
///   duplicate the order.
/// * **Amend** fires each edit at the server immediately, because a line on a
///   kitchen ticket needs a reasoned, audited void — not a silent local edit.
abstract class CartController {
  /// Lines as the waiter sees them, whether local or already on the server.
  List<CartDisplayLine> get lines;

  int get totalCents;

  int get itemCount;

  /// Adding is always allowed while the order is open; the server has the
  /// final say on 86'd dishes.
  Future<void> add(CartLine line);

  /// Some lines can be removed outright; a fired one needs [voidLine] instead.
  bool canDelete(String lineId);

  /// True when removing this line requires a reason (it's on a kitchen ticket).
  bool needsVoidReason(String lineId);

  Future<void> remove(String lineId, {String? reason});

  Future<void> setQty(String lineId, int qty);

  /// Create: places the order and returns its id. Amend: nothing to commit —
  /// every edit already landed — so it returns the existing id.
  Future<String> commit();

  /// Whether [commit] still has work to do (drives the button's wording).
  bool get hasPendingCommit;
}

/// One row in the cart, from either source.
class CartDisplayLine {
  const CartDisplayLine({
    required this.id,
    required this.title,
    required this.qty,
    required this.unitPriceCents,
    required this.canEditQty,
    required this.isFired,
    this.notes,
    this.modifierNames = const [],
  });

  final String id;
  final String title;
  final int qty;
  final int unitPriceCents;
  final bool canEditQty;
  final bool isFired;
  final String? notes;
  final List<String> modifierNames;

  int get lineTotalCents => unitPriceCents * qty;
}

/// Composing a new order. Everything is local until [commit].
class CreateCart implements CartController {
  CreateCart({
    required PosRepository repository,
    required this.orderType,
    this.tableId,
    this.guests,
  }) : _repo = repository;

  final PosRepository _repo;
  final String orderType;
  final String? tableId;
  final int? guests;

  final List<CartLine> _lines = [];
  static const _uuid = Uuid();

  /// Minted once, at first commit attempt, and **reused for every retry**.
  /// A fresh key per attempt is how you get two orders from one tap.
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
  Future<String> commit() async {
    _idempotencyKey ??= _uuid.v4();
    return _repo.placeOrder(
      lines: _lines,
      orderType: orderType,
      tableId: tableId,
      guests: guests,
      idempotencyKey: _idempotencyKey,
    );
  }
}

/// Editing an order that already exists. Every change is a server call.
class AmendCart implements CartController {
  AmendCart({required PosRepository repository, required PosOrder order})
    : _repo = repository,
      _order = order;

  final PosRepository _repo;
  PosOrder _order;

  PosOrder get order => _order;

  /// Replace the snapshot after a refetch, so the cart shows server truth
  /// rather than a frozen copy.
  void update(PosOrder order) => _order = order;

  List<PosOrderLine> get _live => _order.lines.where((l) => !l.isVoid).toList();

  @override
  List<CartDisplayLine> get lines => _live
      .map(
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
      )
      .toList();

  @override
  int get totalCents => _order.totalCents;

  @override
  int get itemCount => _order.itemCount;

  @override
  Future<void> add(CartLine line) =>
      _repo.addItem(orderId: _order.id, line: line);

  @override
  bool canDelete(String lineId) => true;

  @override
  bool needsVoidReason(String lineId) {
    final line = _live.where((l) => l.id == lineId).firstOrNull;
    return line?.isFired ?? false;
  }

  @override
  Future<void> remove(String lineId, {String? reason}) async {
    if (needsVoidReason(lineId)) {
      await _repo.voidLine(lineId: lineId, reason: reason ?? '');
      return;
    }
    await _repo.deleteDraftLine(lineId);
  }

  @override
  Future<void> setQty(String lineId, int qty) =>
      _repo.setLineQty(lineId: lineId, qty: qty);

  /// Nothing is pending: each edit already hit the server.
  @override
  bool get hasPendingCommit => false;

  @override
  Future<String> commit() async => _order.id;
}
