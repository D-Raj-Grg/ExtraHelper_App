/// The server, as the replay engine sees it.
///
/// The engine must distinguish **two kinds of failure** (rule 3), because
/// conflating them is how a real order gets silently dropped:
///
/// * [TransportRejected] — the server understood and said no (permission,
///   constraint, an 86'd dish, a closed order). Retrying will never help, so
///   the entry dies immediately and the waiter is told why.
/// * [TransportTransient] — the write never got an answer (socket, timeout,
///   airplane mode). The same write is owed and gets retried under the same
///   idempotency key.
library;

class TransportRejected implements Exception {
  const TransportRejected(this.message);

  final String message;

  @override
  String toString() => message;
}

class TransportTransient implements Exception {
  const TransportTransient(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract class OutboxTransport {
  /// Returns the server order id. Replaying the same key returns the same id —
  /// `place_staff_order` has a fast-path that answers before any write.
  Future<String> placeOrder({
    required String idempotencyKey,
    required Map<String, dynamic> payload,
  });

  Future<void> addItem({
    required String orderId,
    required Map<String, dynamic> payload,
  });

  Future<void> voidLine({required String orderItemId, required String reason});

  Future<void> fire(String orderId);

  Future<void> setItem86({required String itemId, required bool is86});

  Future<void> setTableState({required String tableId, required String state});

  /// An absolute counted quantity for one line of a stock count.
  Future<void> setCountActual({
    required String countItemId,
    required double actual,
  });

  /// One dish on a kitchen ticket. The RPC re-derives the ticket and the order.
  Future<void> setKotLineStatus({
    required String kotItemId,
    required String status,
  });

  /// A whole kitchen ticket. `recalled` comes through here too — it is a
  /// status, not a separate verb, so the queue needs no extra kind for it.
  Future<void> setKotStatus({required String kotId, required String status});

  /// The waiter carried it to the table.
  Future<void> markOrderServed(String orderId);
}
