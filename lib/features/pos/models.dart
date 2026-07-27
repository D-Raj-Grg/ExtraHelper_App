/// POS domain models. Plain Dart — repositories map PostgREST rows into these
/// so no screen ever touches a `Map<String, dynamic>`.
library;

class PosVariant {
  const PosVariant({
    required this.id,
    required this.name,
    required this.priceDeltaCents,
  });

  final String id;
  final String name;
  final int priceDeltaCents;

  static PosVariant fromRow(Map<String, dynamic> r) => PosVariant(
    id: r['id'] as String,
    name: (r['name'] as String?) ?? '',
    priceDeltaCents: (r['price_delta_cents'] as int?) ?? 0,
  );
}

class PosModifier {
  const PosModifier({
    required this.id,
    required this.name,
    required this.priceCents,
  });

  final String id;
  final String name;
  final int priceCents;

  static PosModifier fromRow(Map<String, dynamic> r) => PosModifier(
    id: r['id'] as String,
    name: (r['name'] as String?) ?? '',
    priceCents: (r['price_cents'] as int?) ?? 0,
  );
}

class PosMenuItem {
  const PosMenuItem({
    required this.id,
    required this.name,
    required this.basePriceCents,
    required this.categoryId,
    required this.is86,
    this.imageUrl,
    this.isVeg,
    this.variants = const [],
    this.modifiers = const [],
  });

  final String id;
  final String name;
  final int basePriceCents;
  final String? categoryId;
  final bool is86;
  final String? imageUrl;

  /// Nullable on purpose — unmarked is a real state and must render nothing.
  final bool? isVeg;

  final List<PosVariant> variants;

  /// Add-ons **linked to this item** via `item_modifiers`. The server rejects
  /// any modifier that isn't, so the picker must only ever offer these.
  final List<PosModifier> modifiers;

  /// Only the stock flag moves at runtime — a Realtime 86 must not rebuild the
  /// dish's price or options from a partial row.
  PosMenuItem copyWith({bool? is86}) => PosMenuItem(
    id: id,
    name: name,
    basePriceCents: basePriceCents,
    categoryId: categoryId,
    is86: is86 ?? this.is86,
    imageUrl: imageUrl,
    isVeg: isVeg,
    variants: variants,
    modifiers: modifiers,
  );

  int get optionCount => variants.length + modifiers.length;

  /// What this dish can actually cost.
  ///
  /// Not `basePriceCents`: when variants exist the options sheet forces a
  /// choice, so the base price alone is a figure nobody can order — the exact
  /// bug the web tile had. Add-ons are excluded because they're optional.
  ({int min, int max}) get priceRange {
    if (variants.isEmpty) return (min: basePriceCents, max: basePriceCents);
    var lo = variants.first.priceDeltaCents;
    var hi = lo;
    for (final v in variants) {
      if (v.priceDeltaCents < lo) lo = v.priceDeltaCents;
      if (v.priceDeltaCents > hi) hi = v.priceDeltaCents;
    }
    return (min: basePriceCents + lo, max: basePriceCents + hi);
  }
}

class PosCategory {
  const PosCategory({required this.id, required this.name, required this.sort});

  final String id;
  final String name;
  final int sort;
}

class PosFloor {
  const PosFloor({required this.id, required this.name, required this.sort});

  final String id;
  final String name;
  final int sort;
}

class PosTable {
  const PosTable({
    required this.id,
    required this.label,
    required this.capacity,
    required this.state,
    this.floorId,
    this.currentOrderId,
  });

  final String id;
  final String label;
  final int capacity;

  /// `free | occupied | reserved | bill_requested | cleaning`
  final String state;
  final String? floorId;
  final String? currentOrderId;

  bool get isFree => state == 'free';

  static PosTable fromRow(Map<String, dynamic> r) => PosTable(
    id: r['id'] as String,
    label: (r['label'] as String?) ?? '?',
    capacity: (r['capacity'] as int?) ?? 2,
    state: (r['state'] as String?) ?? 'free',
    floorId: r['floor_id'] as String?,
    currentOrderId: r['current_order_id'] as String?,
  );

  PosTable copyWith({String? state}) => PosTable(
    id: id,
    label: label,
    capacity: capacity,
    state: state ?? this.state,
    floorId: floorId,
    currentOrderId: currentOrderId,
  );
}

/// A line already on the server.
class PosOrderLine {
  const PosOrderLine({
    required this.id,
    required this.nameSnapshot,
    required this.qty,
    required this.unitPriceCents,
    required this.status,
    required this.isVoid,
    this.notes,
    this.modifierNames = const [],
  });

  final String id;

  /// Already includes the variant — the server writes "Buff Sekuwa (KG)".
  final String nameSnapshot;

  final int qty;
  final int unitPriceCents;

  /// `draft` means not yet fired: it can be deleted outright. Anything else is
  /// on a kitchen ticket and needs a reasoned, audited void.
  final String status;

  final bool isVoid;
  final String? notes;
  final List<String> modifierNames;

  bool get isFired => status != 'draft';
  int get lineTotalCents => unitPriceCents * qty;

  static PosOrderLine fromRow(Map<String, dynamic> r) {
    final mods = (r['order_item_modifiers'] as List<dynamic>? ?? const [])
        .map(
          (m) =>
              ((m as Map<String, dynamic>)['name_snapshot'] as String?) ?? '',
        )
        .where((s) => s.isNotEmpty)
        .toList();
    return PosOrderLine(
      id: r['id'] as String,
      nameSnapshot: (r['name_snapshot'] as String?) ?? '',
      qty: (r['qty'] as int?) ?? 1,
      unitPriceCents: (r['unit_price_cents'] as int?) ?? 0,
      status: (r['status'] as String?) ?? 'draft',
      isVoid: (r['is_void'] as bool?) ?? false,
      notes: r['notes'] as String?,
      modifierNames: mods,
    );
  }
}

class PosOrder {
  const PosOrder({
    required this.id,
    required this.status,
    required this.orderType,
    required this.createdAt,
    this.tableId,
    this.tableLabel,
    this.guests,
    this.lines = const [],
  });

  final String id;
  final String status;
  final String orderType;
  final DateTime createdAt;
  final String? tableId;
  final String? tableLabel;
  final int? guests;
  final List<PosOrderLine> lines;

  /// Voided lines don't count — they were removed from the bill.
  int get totalCents =>
      lines.where((l) => !l.isVoid).fold(0, (sum, l) => sum + l.lineTotalCents);

  int get itemCount =>
      lines.where((l) => !l.isVoid).fold(0, (sum, l) => sum + l.qty);

  bool get canFire => lines.any((l) => !l.isVoid && l.status == 'draft');

  /// Settled or abandoned — no further edits.
  bool get isClosed =>
      status == 'billed' || status == 'closed' || status == 'cancelled';

  static PosOrder fromRow(Map<String, dynamic> r) {
    final table = r['restaurant_tables'] as Map<String, dynamic>?;
    final lines = (r['order_items'] as List<dynamic>? ?? const [])
        .map((l) => PosOrderLine.fromRow(l as Map<String, dynamic>))
        .toList();
    return PosOrder(
      id: r['id'] as String,
      status: (r['status'] as String?) ?? 'draft',
      orderType: (r['order_type'] as String?) ?? 'dine_in',
      createdAt:
          DateTime.tryParse((r['created_at'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      tableId: r['table_id'] as String?,
      tableLabel: table?['label'] as String?,
      guests: r['guests'] as int?,
      lines: lines,
    );
  }
}

/// A line being composed locally, before it exists on the server.
class CartLine {
  const CartLine({
    required this.localId,
    required this.item,
    required this.qty,
    this.variant,
    this.modifiers = const [],
    this.notes,
  });

  /// A stable local id. **Never key a list row by its content** — a signature
  /// key changes on every keystroke, React/Flutter rebuilds the row, and the
  /// caret is lost mid-word. Signatures are for deciding merges only.
  final String localId;

  final PosMenuItem item;
  final int qty;
  final PosVariant? variant;
  final List<PosModifier> modifiers;
  final String? notes;

  int get unitPriceCents =>
      item.basePriceCents +
      (variant?.priceDeltaCents ?? 0) +
      modifiers.fold(0, (s, m) => s + m.priceCents);

  int get lineTotalCents => unitPriceCents * qty;

  /// Display title folds the variant in. Without it two lines both read
  /// "Buff Sekuwa" and differ only by price — a real bug the web hit.
  String get title =>
      variant == null ? item.name : '${item.name} (${variant!.name})';

  /// Identity for merging: same dish, same variant, same add-ons, same note.
  String get signature => [
    item.id,
    variant?.id ?? '',
    (modifiers.map((m) => m.id).toList()..sort()).join(','),
    notes ?? '',
  ].join('|');

  CartLine copyWith({int? qty, String? notes}) => CartLine(
    localId: localId,
    item: item,
    qty: qty ?? this.qty,
    variant: variant,
    modifiers: modifiers,
    notes: notes ?? this.notes,
  );

  Map<String, dynamic> toRpcJson() => {
    'item_id': item.id,
    'qty': qty,
    if (variant != null) 'variant_id': variant!.id,
    if (modifiers.isNotEmpty)
      'modifier_ids': modifiers.map((m) => m.id).toList(),
    if (notes != null && notes!.trim().isNotEmpty) 'notes': notes!.trim(),
  };
}

/// One line of the manager's log: who did a thing, to what, and why.
///
/// Read straight from `audit_logs`, whose RLS already restricts SELECT to
/// owners and managers — so this list cannot leak to a waiter even if the app
/// asked for it.
class PosAuditEntry {
  const PosAuditEntry({
    required this.id,
    required this.action,
    required this.createdAt,
    required this.metadata,
    this.actorName,
  });

  final String id;

  /// `void`, `discount`, `item_86`, `table_state`, ...
  final String action;

  final DateTime createdAt;
  final Map<String, dynamic> metadata;

  /// Null when the actor has no profile row — the log outlives the person.
  final String? actorName;

  /// The reason someone typed, when the action demanded one.
  String? get reason {
    final r = metadata['reason'];
    return (r is String && r.trim().isNotEmpty) ? r.trim() : null;
  }

  /// What the action was done to, in words a manager recognises.
  ///
  /// A void's audit row carries only the reason, so the dish name is looked up
  /// and merged in by the repository — "Void —" tells a manager nothing.
  String get subject {
    for (final key in ['name', 'label', 'name_snapshot']) {
      final v = metadata[key];
      if (v is String && v.isNotEmpty) return v;
    }
    // A discount describes itself by its size when there's nothing else.
    final type = metadata['type'];
    final value = metadata['value'];
    if (type == 'percent' && value is num) return '${_trim(value)}% off';
    if (type == 'flat' && value is num) return '${_trim(value)} off';
    return '—';
  }

  static String _trim(num v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  static PosAuditEntry fromRow(Map<String, dynamic> r) {
    final meta = r['metadata'];
    final actor = r['actor'] as Map<String, dynamic>?;
    return PosAuditEntry(
      id: r['id'] as String,
      action: (r['action'] as String?) ?? '',
      createdAt:
          DateTime.tryParse((r['created_at'] as String?) ?? '')?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      metadata: meta is Map<String, dynamic> ? meta : const {},
      // `full_name` is often unset; the username is what the person actually
      // has. Either beats "someone".
      actorName:
          (actor?['full_name'] as String?) ?? (actor?['username'] as String?),
    );
  }
}
