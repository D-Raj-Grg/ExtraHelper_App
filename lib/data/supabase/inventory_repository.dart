import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'pos_repository.dart' show PosFailure, PosTransientFailure;
import 'supabase_providers.dart';

/// One thing the store room keeps.
///
/// Quantities are `numeric` in Postgres, which PostgREST hands over as a
/// **string** ("3.750"). Parsing them as `num` would throw on a good row, so
/// everything numeric goes through [_num] — the same lesson the dashboard
/// envelope learned.
class InventoryItem {
  const InventoryItem({
    required this.id,
    required this.name,
    required this.uom,
    required this.currentQty,
    required this.reorderLevel,
    required this.costCents,
    this.category,
    this.barcode,
  });

  final String id;
  final String name;
  final String uom;
  final double currentQty;
  final double reorderLevel;
  final int costCents;
  final String? category;

  /// Null for most items. The scanner falls back to search when it is.
  final String? barcode;

  /// Below the level someone said to reorder at. The same comparison the web
  /// dashboard and `/inventory` make, so one item is never "low" on one screen
  /// and fine on the other.
  bool get isLow => currentQty < reorderLevel;

  static InventoryItem fromJson(Map<String, dynamic> j) => InventoryItem(
    id: (j['id'] as String?) ?? '',
    name: (j['name'] as String?) ?? '',
    uom: (j['uom'] as String?) ?? 'unit',
    currentQty: _num(j['current_qty']),
    reorderLevel: _num(j['reorder_level']),
    costCents: _num(j['cost_cents']).round(),
    category: j['category'] as String?,
    barcode: j['barcode'] as String?,
  );
}

/// A count in progress. A posted count is history and cannot be edited.
class StockCount {
  const StockCount({required this.id, required this.postedAt});

  final String id;
  final DateTime? postedAt;

  bool get isOpen => postedAt == null;

  static StockCount fromJson(Map<String, dynamic> j) => StockCount(
    id: (j['id'] as String?) ?? '',
    postedAt: DateTime.tryParse((j['posted_at'] as String?) ?? ''),
  );
}

/// One line of a count: what the system thinks is there, and what someone
/// standing in the store room actually found.
class StockCountLine {
  const StockCountLine({
    required this.id,
    required this.itemId,
    required this.name,
    required this.uom,
    required this.theoreticalQty,
    this.actualQty,
    this.barcode,
  });

  final String id;
  final String itemId;
  final String name;
  final String uom;
  final double theoreticalQty;

  /// Null until someone counts it — **not zero**. "Nobody has been to that
  /// shelf yet" and "the shelf is empty" are different facts, and posting
  /// treats them differently.
  final double? actualQty;

  final String? barcode;

  bool get isCounted => actualQty != null;

  /// Positive = more on the shelf than the system thought.
  double? get variance =>
      actualQty == null ? null : actualQty! - theoreticalQty;

  StockCountLine copyWith({double? actualQty}) => StockCountLine(
    id: id,
    itemId: itemId,
    name: name,
    uom: uom,
    theoreticalQty: theoreticalQty,
    actualQty: actualQty ?? this.actualQty,
    barcode: barcode,
  );

  static StockCountLine fromJson(Map<String, dynamic> j) {
    final item = (j['inventory_items'] as Map<String, dynamic>?) ?? const {};
    return StockCountLine(
      id: (j['id'] as String?) ?? '',
      itemId: (j['inventory_item_id'] as String?) ?? '',
      name: (item['name'] as String?) ?? '',
      uom: (item['uom'] as String?) ?? 'unit',
      theoreticalQty: _num(j['theoretical_qty']),
      actualQty: j['actual_qty'] == null ? null : _num(j['actual_qty']),
      barcode: item['barcode'] as String?,
    );
  }
}

/// Why stock moved. Mirrors the `stock_movement_type` enum; `sale` and `count`
/// are written by the server (recipe deduction, posting a count) and are
/// deliberately not offerable here.
enum StockMovementType { purchase, wastage, staffMeal, transfer, adjustment }

extension StockMovementTypeX on StockMovementType {
  String get wire => switch (this) {
    StockMovementType.purchase => 'purchase',
    StockMovementType.wastage => 'wastage',
    StockMovementType.staffMeal => 'staff_meal',
    StockMovementType.transfer => 'transfer',
    StockMovementType.adjustment => 'adjustment',
  };

  String get label => switch (this) {
    StockMovementType.purchase => 'Delivery in',
    StockMovementType.wastage => 'Wastage',
    StockMovementType.staffMeal => 'Staff meal',
    StockMovementType.transfer => 'Transfer out',
    StockMovementType.adjustment => 'Correction',
  };

  /// A write-off needs a reason. The others are self-explanatory movements.
  bool get needsReason => this == StockMovementType.wastage;
}

double _num(Object? v) => switch (v) {
  num() => v.toDouble(),
  String() => double.tryParse(v) ?? 0,
  _ => 0,
};

/// Reads and writes for the store room.
///
/// Every write is an RPC that enforces its own rule: `adjust_inventory` and
/// `set_stock_count_actual` gate on `inventory.edit`, `post_stock_count` on the
/// inventory roles, and all three audit. RLS on these tables is tenant-scoped
/// only, so the RPC — not the app — is the boundary. Reads still carry an
/// explicit tenant filter as defense in depth (rule 2).
class InventoryRepository {
  const InventoryRepository(this._client, this._tenantId);

  final SupabaseClient _client;
  final String _tenantId;

  static const _columns =
      'id, name, uom, category, current_qty, reorder_level, cost_cents, barcode';

  Future<List<InventoryItem>> items() async {
    try {
      final rows = await _client
          .from('inventory_items')
          .select(_columns)
          .eq('tenant_id', _tenantId)
          .order('name');
      return rows.map(InventoryItem.fromJson).toList();
    } catch (_) {
      throw const PosTransientFailure("Couldn't load the store room.");
    }
  }

  /// The item carrying this scanned code, or null when nothing does.
  ///
  /// `maybeSingle` rather than `single`: an unknown code is an ordinary event
  /// in a store room, not an error.
  Future<InventoryItem?> byBarcode(String code) async {
    try {
      final row = await _client
          .from('inventory_items')
          .select(_columns)
          .eq('tenant_id', _tenantId)
          .eq('barcode', code)
          .maybeSingle();
      return row == null ? null : InventoryItem.fromJson(row);
    } catch (_) {
      throw const PosTransientFailure("Couldn't look that code up.");
    }
  }

  /// The count still open, if there is one. Only one can be open at a time in
  /// practice, and the newest is the one someone is standing in front of.
  Future<StockCount?> openCount() async {
    try {
      final rows = await _client
          .from('stock_counts')
          .select('id, posted_at')
          .eq('tenant_id', _tenantId)
          .isFilter('posted_at', null)
          .order('created_at', ascending: false)
          .limit(1);
      return rows.isEmpty ? null : StockCount.fromJson(rows.first);
    } catch (_) {
      throw const PosTransientFailure("Couldn't check for an open count.");
    }
  }

  /// Open a count. The RPC snapshots current on-hand as each line's
  /// theoretical quantity, so the variance means something later.
  Future<String> startCount() async {
    try {
      final id = await _client.rpc<dynamic>(
        'start_stock_count',
        params: {'_tenant': _tenantId},
      );
      return id as String;
    } on PostgrestException catch (e) {
      throw PosFailure(_friendly(e.message));
    } catch (_) {
      throw const PosTransientFailure(
        "Couldn't start a count. Nothing was opened.",
      );
    }
  }

  Future<List<StockCountLine>> countLines(String countId) async {
    try {
      final rows = await _client
          .from('stock_count_items')
          .select(
            'id, inventory_item_id, theoretical_qty, actual_qty, '
            'inventory_items(name, uom, barcode)',
          )
          .eq('tenant_id', _tenantId)
          .eq('stock_count_id', countId);
      final lines = rows.map(StockCountLine.fromJson).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      return lines;
    } catch (_) {
      throw const PosTransientFailure("Couldn't load the count.");
    }
  }

  /// Record a counted quantity. **Absolute**, which is what makes it safe to
  /// queue: replaying it just writes the same number again.
  Future<void> setCountActual({
    required String countItemId,
    required double actual,
  }) async {
    try {
      await _client.rpc<dynamic>(
        'set_stock_count_actual',
        params: {'_count_item_id': countItemId, '_actual': actual},
      );
    } on PostgrestException catch (e) {
      throw PosFailure(_friendly(e.message));
    } catch (_) {
      throw const PosTransientFailure("Couldn't save that count.");
    }
  }

  /// Reconcile on-hand to what was counted. Writes a `count` movement per
  /// changed line and an audit row.
  Future<int> postCount(String countId) async {
    try {
      final n = await _client.rpc<dynamic>(
        'post_stock_count',
        params: {'_count_id': countId},
      );
      return (n as num?)?.toInt() ?? 0;
    } on PostgrestException catch (e) {
      throw PosFailure(_friendly(e.message));
    } catch (_) {
      throw const PosTransientFailure(
        "Couldn't post the count. Nothing was changed.",
      );
    }
  }

  /// Move stock by a delta. **Never queued** — a delta replayed twice moves
  /// stock twice, and `adjust_inventory` takes no idempotency key.
  Future<double> adjust({
    required String itemId,
    required double delta,
    required StockMovementType type,
    String reason = '',
  }) async {
    try {
      final qty = await _client.rpc<dynamic>(
        'adjust_inventory',
        params: {
          '_item': itemId,
          '_delta': delta,
          '_type': type.wire,
          '_reason': reason,
        },
      );
      return _num(qty);
    } on PostgrestException catch (e) {
      throw PosFailure(_friendly(e.message));
    } catch (_) {
      throw const PosTransientFailure(
        "Couldn't reach the server. Stock was not changed.",
      );
    }
  }
}

/// Server prose → something a store keeper can act on. The RPC messages are
/// already written for people; this only softens the ones that aren't.
String _friendly(String raw) {
  final m = raw.toLowerCase();
  if (m.contains('not authorized')) {
    return "Your role can't change stock here. An owner or manager can grant "
        'that under Team.';
  }
  if (m.contains('already posted')) {
    return 'That count was already posted, so it can no longer be edited.';
  }
  if (m.contains('inventory item not found') || m.contains('not found')) {
    return 'That item no longer exists. Pull to refresh.';
  }
  return raw;
}

final inventoryRepositoryProvider =
    Provider.family<InventoryRepository, String>(
      (ref, tenantId) =>
          InventoryRepository(ref.watch(supabaseProvider), tenantId),
    );
