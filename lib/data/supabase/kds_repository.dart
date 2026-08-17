import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/kds/kds_constants.dart';
import 'pos_repository.dart' show PosFailure, PosTransientFailure;
import 'supabase_providers.dart';

/// One dish on a ticket.
class KdsLine {
  const KdsLine({
    required this.id,
    required this.orderItemId,
    required this.name,
    required this.qty,
    required this.status,
    required this.isVoid,
    this.notes,
    this.modifiers = const [],
  });

  final String id;
  final String orderItemId;
  final String name;
  final int qty;
  final KotStatus status;

  /// A cancelled dish stays on the ticket, struck through: the cook needs to
  /// know it was there and is not coming.
  final bool isVoid;

  final String? notes;
  final List<String> modifiers;

  KdsLine copyWith({KotStatus? status}) => KdsLine(
    id: id,
    orderItemId: orderItemId,
    name: name,
    qty: qty,
    status: status ?? this.status,
    isVoid: isVoid,
    notes: notes,
    modifiers: modifiers,
  );

  static KdsLine fromJson(Map<String, dynamic> j) {
    final item = (j['order_items'] as Map<String, dynamic>?) ?? const {};
    final mods = (item['order_item_modifiers'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((m) {
          final name = (m['name_snapshot'] as String?) ?? '';
          final qty = (m['qty'] as num?)?.toInt() ?? 1;
          return qty > 1 ? '$name ×$qty' : name;
        })
        .where((s) => s.isNotEmpty)
        .toList();

    return KdsLine(
      id: (j['id'] as String?) ?? '',
      orderItemId: (item['id'] as String?) ?? '',
      name: (item['name_snapshot'] as String?) ?? 'item',
      qty: (j['qty'] as num?)?.toInt() ?? 1,
      status: kotStatusFrom((j['status'] as String?) ?? 'new'),
      isVoid: (item['is_void'] as bool?) ?? false,
      notes: item['notes'] as String?,
      modifiers: mods,
    );
  }
}

/// One station's ticket for one order.
class KdsTicket {
  const KdsTicket({
    required this.id,
    required this.status,
    required this.createdAt,
    required this.orderId,
    required this.lines,
    required this.station,
    required this.printed,
    this.stationId,
    this.tableLabel,
    this.orderStatus,
  });

  final String id;
  final KotStatus status;
  final DateTime createdAt;
  final String orderId;
  final List<KdsLine> lines;

  /// "Expo" when a dish routes to no station — the same fallback the web board
  /// and `fire_order` use.
  final String station;
  final String? stationId;

  final bool printed;
  final String? tableLabel;
  final String? orderStatus;

  /// Lines that still count. A fully-voided ticket derives nothing.
  List<KdsLine> get live => lines.where((l) => !l.isVoid).toList();

  String get destination =>
      tableLabel == null ? 'Takeaway' : 'Table $tableLabel';

  /// Whether this ticket is finished, and therefore off the pass.
  ///
  /// **The order half matters as much as the kitchen half.** A ticket the
  /// kitchen never bumped, on an order that has since been closed or
  /// cancelled, is history: the food went out, the guest paid and left. Without
  /// this it sat on the board forever, and every cook learned to ignore the
  /// bottom of the list. The web settled the same rule in `isKotCompleted`.
  ///
  /// `billed` is **not** in that set, and leaving it in was a live hole: the
  /// amend RPCs now take new items on a `billed` order while its bill is
  /// unpaid, and firing them makes a real ticket on an order that stays
  /// `billed`. Counting that as history hid the round from the only screen the
  /// kitchen looks at — the guest was charged for food nobody ever cooked.
  /// `closed` is the status that means paid, and it is the one that belongs
  /// here.
  bool get isCompleted =>
      status == KotStatus.served ||
      const {'closed', 'cancelled'}.contains(orderStatus);

  /// The ticket is its least-advanced live line — the same rank ladder
  /// `set_kot_item_status` uses server-side, so an optimistic tap agrees with
  /// what comes back.
  KotStatus get derived {
    final open = live;
    if (open.isEmpty) return status;
    final rank = open
        .map((l) => kotStatusRank(l.status))
        .reduce((a, b) => a < b ? a : b);
    return kotStatusOfRank(rank);
  }

  KdsTicket copyWith({KotStatus? status, List<KdsLine>? lines}) => KdsTicket(
    id: id,
    status: status ?? this.status,
    createdAt: createdAt,
    orderId: orderId,
    lines: lines ?? this.lines,
    station: station,
    stationId: stationId,
    printed: printed,
    tableLabel: tableLabel,
    orderStatus: orderStatus,
  );

  static KdsTicket fromJson(Map<String, dynamic> j) {
    final station =
        (j['kitchen_stations'] as Map<String, dynamic>?)?['name'] as String?;
    final order = (j['orders'] as Map<String, dynamic>?) ?? const {};
    final table =
        (order['restaurant_tables'] as Map<String, dynamic>?)?['label']
            as String?;

    final lines = (j['kot_items'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(KdsLine.fromJson)
        .toList();

    return KdsTicket(
      id: (j['id'] as String?) ?? '',
      status: kotStatusFrom((j['status'] as String?) ?? 'new'),
      createdAt:
          DateTime.tryParse((j['created_at'] as String?) ?? '')?.toLocal() ??
          DateTime.now(),
      orderId: (j['order_id'] as String?) ?? '',
      lines: lines,
      station: station ?? 'Expo',
      stationId: j['station_id'] as String?,
      printed: j['printed_at'] != null,
      tableLabel: table,
      orderStatus: order['status'] as String?,
    );
  }
}

/// A kitchen station, for the board's filter.
class KitchenStation {
  const KitchenStation({required this.id, required this.name});

  final String id;
  final String name;

  static KitchenStation fromJson(Map<String, dynamic> j) => KitchenStation(
    id: (j['id'] as String?) ?? '',
    name: (j['name'] as String?) ?? '',
  );
}

/// Reads and writes for the kitchen board.
///
/// Every write is an RPC that enforces its own rule: `set_kot_item_status`,
/// `set_kot_status` and `recall_kot` gate on `kds.bump`, `mark_kot_printed` on
/// `kds.view`. RLS on `kots` and `kot_items` is tenant-scoped only, so the RPC
/// — not the app — is the boundary. That is exactly what was wrong with the
/// web's old ticket path, and why these functions exist.
class KdsRepository {
  const KdsRepository(this._client, this._tenantId);

  final SupabaseClient _client;
  final String _tenantId;

  /// Tickets on the board: everything live, plus recently-served ones so a
  /// bump made by mistake can be pulled back.
  Future<List<KdsTicket>> tickets() async {
    try {
      final since = DateTime.now().toUtc().subtract(recallWindow);
      final rows = await _client
          .from('kots')
          .select(kdsSelect)
          .eq('tenant_id', _tenantId)
          .or(
            'status.in.(new,preparing,ready,recalled),'
            'and(status.eq.served,created_at.gte.${since.toIso8601String()})',
          )
          .order('created_at', ascending: true);
      return rows
          .map((r) => KdsTicket.fromJson(r))
          .where((t) => t.lines.isNotEmpty)
          .toList();
    } catch (_) {
      throw const PosTransientFailure("Couldn't load the kitchen board.");
    }
  }

  Future<List<KitchenStation>> stations() async {
    try {
      final rows = await _client
          .from('kitchen_stations')
          .select('id, name')
          .eq('tenant_id', _tenantId)
          .order('name');
      return rows.map(KitchenStation.fromJson).toList();
    } catch (_) {
      throw const PosTransientFailure("Couldn't load the stations.");
    }
  }

  /// One dish. The RPC re-derives the ticket from its lines and the order from
  /// its tickets, so a cook can plate dish by dish.
  Future<void> setLineStatus(String kotItemId, KotStatus status) => _write(
    'set_kot_item_status',
    {'_kot_item_id': kotItemId, '_status': kotStatusWire(status)},
    "Couldn't move that dish.",
  );

  /// The whole ticket, voided lines left alone.
  Future<void> setTicketStatus(String kotId, KotStatus status) => _write(
    'set_kot_status',
    {'_kot_id': kotId, '_status': kotStatusWire(status)},
    "Couldn't move that ticket.",
  );

  /// Pull a bumped ticket back onto the board. Audited server-side.
  Future<void> recall(String kotId) =>
      _write('recall_kot', {'_kot_id': kotId}, "Couldn't recall that ticket.");

  Future<void> markPrinted(String kotId) => _write('mark_kot_printed', {
    '_kot_id': kotId,
  }, "Couldn't record that print.");

  /// The waiter carried it to the table. `mark_order_served` allows waiters and
  /// cashiers as well as the kitchen, and refuses an order that is already
  /// billed — so `served` means "it reached the guest", not "the kitchen
  /// finished".
  Future<void> markOrderServed(String orderId) => _write('mark_order_served', {
    '_order_id': orderId,
  }, "Couldn't mark that delivered.");

  /// Server prose reaches the cook rather than being swallowed: "not authorized
  /// to move a ticket" is something a person can act on.
  Future<void> _write(
    String fn,
    Map<String, dynamic> params,
    String transient,
  ) async {
    try {
      await _client.rpc<dynamic>(fn, params: params);
    } on PostgrestException catch (e) {
      throw PosFailure(e.message);
    } catch (_) {
      throw PosTransientFailure(transient);
    }
  }
}

final kdsRepositoryProvider = Provider.family<KdsRepository, String>(
  (ref, tenantId) => KdsRepository(ref.watch(supabaseProvider), tenantId),
);
