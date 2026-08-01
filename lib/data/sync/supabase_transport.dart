import '../../features/kds/kds_constants.dart';
import '../supabase/inventory_repository.dart';
import '../supabase/kds_repository.dart';
import '../supabase/pos_repository.dart';
import 'transport.dart';

/// The real server behind the outbox.
///
/// Its whole job is the rule-3 split: [PosTransientFailure] is still owed and
/// gets retried; anything else the repository raised was a considered "no" from
/// Postgres and must not be retried into a silent loop.
class SupabaseTransport implements OutboxTransport {
  const SupabaseTransport(this._repo, this._inventory, this._kds);

  final PosRepository _repo;
  final InventoryRepository _inventory;
  final KdsRepository _kds;

  @override
  Future<String> placeOrder({
    required String idempotencyKey,
    required Map<String, dynamic> payload,
  }) async {
    final items = (payload['items'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    try {
      return await _repo.placeOrderJson(
        items: items,
        orderType: payload['order_type'] as String,
        tableId: payload['table_id'] as String?,
        guests: payload['guests'] as int?,
        idempotencyKey: idempotencyKey,
      );
    } on PosTransientFailure catch (e) {
      throw TransportTransient(e.message);
    } on PosFailure catch (e) {
      throw TransportRejected(e.message);
    }
  }

  @override
  Future<void> addItem({
    required String orderId,
    required Map<String, dynamic> payload,
  }) async {
    try {
      await _repo.addItemJson(orderId: orderId, item: payload);
    } on PosTransientFailure catch (e) {
      throw TransportTransient(e.message);
    } on PosFailure catch (e) {
      throw TransportRejected(e.message);
    }
  }

  @override
  Future<void> voidLine({
    required String orderItemId,
    required String reason,
  }) async {
    try {
      await _repo.voidLine(lineId: orderItemId, reason: reason);
    } on PosTransientFailure catch (e) {
      throw TransportTransient(e.message);
    } on PosFailure catch (e) {
      throw TransportRejected(e.message);
    }
  }

  @override
  Future<void> fire(String orderId) async {
    try {
      await _repo.fireOrder(orderId);
    } on PosTransientFailure catch (e) {
      throw TransportTransient(e.message);
    } on PosFailure catch (e) {
      throw TransportRejected(e.message);
    }
  }

  @override
  Future<void> setItem86({required String itemId, required bool is86}) async {
    try {
      await _repo.setItem86(itemId: itemId, is86: is86);
    } on PosTransientFailure catch (e) {
      throw TransportTransient(e.message);
    } on PosFailure catch (e) {
      throw TransportRejected(e.message);
    }
  }

  @override
  Future<void> setTableState({
    required String tableId,
    required String state,
  }) async {
    try {
      await _repo.setTableState(tableId: tableId, state: state);
    } on PosTransientFailure catch (e) {
      throw TransportTransient(e.message);
    } on PosFailure catch (e) {
      throw TransportRejected(e.message);
    }
  }

  @override
  Future<void> setCountActual({
    required String countItemId,
    required double actual,
  }) async {
    try {
      await _inventory.setCountActual(countItemId: countItemId, actual: actual);
    } on PosTransientFailure catch (e) {
      throw TransportTransient(e.message);
    } on PosFailure catch (e) {
      throw TransportRejected(e.message);
    }
  }

  @override
  Future<void> setKotLineStatus({
    required String kotItemId,
    required String status,
  }) async {
    try {
      await _kds.setLineStatus(kotItemId, kotStatusFrom(status));
    } on PosTransientFailure catch (e) {
      throw TransportTransient(e.message);
    } on PosFailure catch (e) {
      throw TransportRejected(e.message);
    }
  }

  @override
  Future<void> setKotStatus({
    required String kotId,
    required String status,
  }) async {
    try {
      await _kds.setTicketStatus(kotId, kotStatusFrom(status));
    } on PosTransientFailure catch (e) {
      throw TransportTransient(e.message);
    } on PosFailure catch (e) {
      throw TransportRejected(e.message);
    }
  }

  @override
  Future<void> markOrderServed(String orderId) async {
    try {
      await _kds.markOrderServed(orderId);
    } on PosTransientFailure catch (e) {
      throw TransportTransient(e.message);
    } on PosFailure catch (e) {
      throw TransportRejected(e.message);
    }
  }
}
