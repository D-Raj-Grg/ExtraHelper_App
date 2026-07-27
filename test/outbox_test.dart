import 'package:extrahelper/data/sync/order_queue.dart';
import 'package:extrahelper/data/sync/outbox.dart';
import 'package:extrahelper/data/sync/replay_engine.dart';
import 'package:extrahelper/data/sync/transport.dart';
import 'package:extrahelper/features/pos/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// A server that records what it was asked to do and can be told how to fail.
/// `place_staff_order`'s replay fast-path is modelled honestly: the same
/// idempotency key returns the same order id and creates nothing new.
class FakeTransport implements OutboxTransport {
  FakeTransport();

  final List<String> calls = [];
  final Map<String, String> _ordersByKey = {};
  int createdOrders = 0;

  /// Thrown on the next call, then cleared. Set a list to script a sequence.
  final List<Object?> failures = [];

  Object? _nextFailure() => failures.isEmpty ? null : failures.removeAt(0);

  void _maybeThrow() {
    final f = _nextFailure();
    if (f != null) throw f;
  }

  @override
  Future<String> placeOrder({
    required String idempotencyKey,
    required Map<String, dynamic> payload,
  }) async {
    calls.add('placeOrder:$idempotencyKey');
    _maybeThrow();
    final existing = _ordersByKey[idempotencyKey];
    if (existing != null) return existing; // replay fast-path
    createdOrders++;
    final id = 'order-$createdOrders';
    _ordersByKey[idempotencyKey] = id;
    return id;
  }

  @override
  Future<void> addItem({
    required String orderId,
    required Map<String, dynamic> payload,
  }) async {
    calls.add('addItem:$orderId:${payload['item_id']}');
    _maybeThrow();
  }

  @override
  Future<void> voidLine({
    required String orderItemId,
    required String reason,
  }) async {
    calls.add('voidLine:$orderItemId');
    _maybeThrow();
  }

  @override
  Future<void> fire(String orderId) async {
    calls.add('fire:$orderId');
    _maybeThrow();
  }
}

CartLine _line(String itemId, {int qty = 1}) => CartLine(
  localId: 'local-$itemId',
  item: PosMenuItem(
    id: itemId,
    name: 'Dish $itemId',
    basePriceCents: 1000,
    categoryId: null,
    is86: false,
  ),
  qty: qty,
);

({
  MemoryOutboxStore store,
  FakeTransport transport,
  ReplayEngine engine,
  OrderQueue queue,
})
_harness({bool online = true}) {
  var isOnline = online;
  final store = MemoryOutboxStore();
  final transport = FakeTransport();
  final engine = ReplayEngine(
    store: store,
    transport: transport,
    isOnline: () async => isOnline,
  );
  final queue = OrderQueue(store: store, engine: engine, tenantId: 'tenant-1');
  return (store: store, transport: transport, engine: engine, queue: queue);
}

void main() {
  group('enqueue', () {
    test('the same idempotency key never produces two rows', () async {
      final h = _harness();

      await h.queue.placeOrder(
        lines: [_line('a')],
        orderType: 'dine_in',
        tableId: 't1',
        idempotencyKey: 'key-1',
      );
      await h.queue.placeOrder(
        lines: [_line('a')],
        orderType: 'dine_in',
        tableId: 't1',
        idempotencyKey: 'key-1',
      );

      expect((await h.store.all()).length, 1);
      expect(h.transport.createdOrders, 1);
    });

    test('an online write is enqueued first, then attempted', () async {
      final h = _harness();

      final outcome = await h.queue.placeOrder(
        lines: [_line('a')],
        orderType: 'pickup',
      );

      // Durable either way — the row exists, and it carries the server id.
      expect((await h.store.all()).length, 1);
      expect(outcome.synced, isTrue);
      expect(outcome.orderRef, 'order-1');
      expect((await h.store.all()).single.state, OutboxState.done);
    });
  });

  group('offline', () {
    test(
      'an order composed offline stays owed, then lands exactly once',
      () async {
        var online = false;
        final store = MemoryOutboxStore();
        final transport = FakeTransport();
        final engine = ReplayEngine(
          store: store,
          transport: transport,
          isOnline: () async => online,
        );
        final queue = OrderQueue(
          store: store,
          engine: engine,
          tenantId: 'tenant-1',
        );

        final placed = await queue.placeOrder(
          lines: [_line('a')],
          orderType: 'dine_in',
          tableId: 't1',
          fire: true,
        );

        expect(placed.synced, isFalse);
        expect(OrderQueue.isDraftRef(placed.orderRef), isTrue);
        expect(transport.calls, isEmpty);
        expect(await queue.pendingCount(), 1);

        online = true;
        await engine.run();
        // A second drain must not re-send anything.
        await engine.run();

        expect(transport.createdOrders, 1);
        expect(transport.calls.where((c) => c.startsWith('fire:')).length, 1);
        expect(await queue.pendingCount(), 0);
      },
    );

    test('an amend against an unsynced order merges into its create', () async {
      var online = false;
      final store = MemoryOutboxStore();
      final transport = FakeTransport();
      final engine = ReplayEngine(
        store: store,
        transport: transport,
        isOnline: () async => online,
      );
      final queue = OrderQueue(
        store: store,
        engine: engine,
        tenantId: 'tenant-1',
      );

      final placed = await queue.placeOrder(
        lines: [_line('a')],
        orderType: 'dine_in',
        tableId: 't1',
      );
      await queue.addItem(orderRef: placed.orderRef, line: _line('b'));

      // One op, two dishes — never an amend the server could not resolve.
      final rows = await store.all();
      expect(rows.length, 1);
      expect((rows.single.payload['items'] as List).length, 2);

      online = true;
      await engine.run();

      expect(transport.createdOrders, 1);
      expect(transport.calls.any((c) => c.startsWith('addItem:')), isFalse);
    });

    test(
      'replay is serial: the create lands before the amends behind it',
      () async {
        var online = false;
        final store = MemoryOutboxStore();
        final transport = FakeTransport();
        final engine = ReplayEngine(
          store: store,
          transport: transport,
          isOnline: () async => online,
        );
        final queue = OrderQueue(
          store: store,
          engine: engine,
          tenantId: 'tenant-1',
        );

        final placed = await queue.placeOrder(
          lines: [_line('a')],
          orderType: 'dine_in',
        );
        // Pretend the create already went out, so the amend cannot merge.
        await store.markInflight(1);
        await queue.addItem(orderRef: placed.orderRef, line: _line('b'));
        await queue.fire(placed.orderRef);

        online = true;
        await engine.run();

        expect(transport.calls, [
          'placeOrder:${(await store.byId(1))!.idempotencyKey}',
          'addItem:order-1:b',
          'fire:order-1',
        ]);
      },
    );
  });

  group('failure handling', () {
    test('a server reject dies immediately, with the reason kept', () async {
      final h = _harness();
      h.transport.failures.add(
        const TransportRejected("Momo is 86'd right now."),
      );

      final outcome = await h.queue.placeOrder(
        lines: [_line('a')],
        orderType: 'dine_in',
      );

      final row = (await h.store.all()).single;
      expect(row.state, OutboxState.dead);
      expect(row.attempts, 0, reason: 'a reject is not a retry');
      expect(row.lastError, "Momo is 86'd right now.");
      expect(outcome.isRejected, isTrue);
      expect(outcome.error, "Momo is 86'd right now.");

      await h.engine.run();
      expect(h.transport.calls.length, 1, reason: 'dead rows are not retried');
    });

    test('six transient failures: dead after five, error preserved', () async {
      final h = _harness();
      for (var i = 0; i < 6; i++) {
        h.transport.failures.add(
          const TransportTransient('Network unreachable'),
        );
      }

      await h.queue.placeOrder(lines: [_line('a')], orderType: 'dine_in');
      for (var i = 0; i < 5; i++) {
        await h.engine.run();
      }

      final row = (await h.store.all()).single;
      expect(row.state, OutboxState.dead);
      expect(row.attempts, 4, reason: '5 attempts made; the 5th killed it');
      expect(row.lastError, 'Network unreachable');
      expect(h.transport.calls.length, 5, reason: 'capped at 5 attempts');
    });

    test(
      'a transient failure recovers under the SAME key, no duplicate',
      () async {
        final h = _harness();
        h.transport.failures.add(const TransportTransient('Timed out'));

        final outcome = await h.queue.placeOrder(
          lines: [_line('a')],
          orderType: 'dine_in',
        );
        expect(outcome.synced, isFalse);
        final key = (await h.store.all()).single.idempotencyKey;

        await h.engine.run();

        expect(h.transport.calls, ['placeOrder:$key', 'placeOrder:$key']);
        expect(h.transport.createdOrders, 1);
        expect((await h.store.all()).single.state, OutboxState.done);
      },
    );

    test(
      'amends behind a dead create are failed, not thrown at the server',
      () async {
        var online = false;
        final store = MemoryOutboxStore();
        final transport = FakeTransport();
        final engine = ReplayEngine(
          store: store,
          transport: transport,
          isOnline: () async => online,
        );
        final queue = OrderQueue(
          store: store,
          engine: engine,
          tenantId: 'tenant-1',
        );

        final placed = await queue.placeOrder(
          lines: [_line('a')],
          orderType: 'dine_in',
        );
        await store.markInflight(1);
        await queue.addItem(orderRef: placed.orderRef, line: _line('b'));

        transport.failures.add(
          const TransportRejected('That table is closed.'),
        );
        online = true;
        await engine.run();

        final rows = await store.all();
        expect(rows[0].state, OutboxState.dead);
        expect(rows[1].state, OutboxState.dead);
        expect(rows[1].lastError, contains('never reached the server'));
        expect(transport.calls.any((c) => c.startsWith('addItem:')), isFalse);
      },
    );
  });

  group('restart safety', () {
    test(
      'a row killed mid-inflight is re-attempted under the same key',
      () async {
        final store = MemoryOutboxStore();
        final transport = FakeTransport();
        final engine = ReplayEngine(
          store: store,
          transport: transport,
          isOnline: () async => true,
        );

        // Exactly the state a kill mid-call leaves behind: persisted `inflight`.
        final entry = await store.enqueue(
          tenantId: 'tenant-1',
          kind: OutboxKind.order,
          orderRef: 'draft:x',
          idempotencyKey: 'key-survivor',
          payload: {
            'order_type': 'dine_in',
            'items': [
              {'item_id': 'a', 'qty': 1},
            ],
            'fire': false,
          },
        );
        await store.markInflight(entry.id);

        await engine.run();

        expect(transport.calls, ['placeOrder:key-survivor']);
        expect(transport.createdOrders, 1);
        expect((await store.byId(entry.id))!.state, OutboxState.done);

        // And if the server had in fact committed it before the kill, the replay
        // fast-path returns the same order rather than making a second one.
        await store.markInflight(entry.id);
        await engine.run();
        expect(transport.createdOrders, 1);
      },
    );

    test('two drains cannot run at once', () async {
      final h = _harness();
      await h.queue.placeOrder(lines: [_line('a')], orderType: 'dine_in');
      final first = h.engine.run();
      final second = h.engine.run();
      expect(await second, 0);
      await first;
    });
  });
}
