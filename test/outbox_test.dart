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

  @override
  Future<void> setItem86({required String itemId, required bool is86}) async {
    calls.add('setItem86:$itemId:$is86');
    _maybeThrow();
  }

  @override
  Future<void> setTableState({
    required String tableId,
    required String state,
  }) async {
    calls.add('setTableState:$tableId:$state');
    _maybeThrow();
  }

  @override
  Future<void> setCountActual({
    required String countItemId,
    required double actual,
  }) async {
    calls.add('setCountActual:$countItemId:$actual');
    _maybeThrow();
  }

  @override
  Future<void> setKotLineStatus({
    required String kotItemId,
    required String status,
  }) async {
    calls.add('setKotLineStatus:$kotItemId:$status');
    _maybeThrow();
  }

  @override
  Future<void> setKotStatus({
    required String kotId,
    required String status,
  }) async {
    calls.add('setKotStatus:$kotId:$status');
    _maybeThrow();
  }

  @override
  Future<void> markOrderServed(String orderId) async {
    calls.add('markOrderServed:$orderId');
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

  group('manager ops', () {
    test(
      'an 86 queued offline reaches the server when coverage returns',
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

        final outcome = await queue.setItem86(itemId: 'item-1', is86: true);
        expect(outcome.synced, isFalse);
        expect(transport.calls, isEmpty);

        online = true;
        await engine.run();

        expect(transport.calls, ['setItem86:item-1:true']);
        expect(await queue.pendingCount(), 0);
      },
    );

    test('a table state change queues and replays', () async {
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

      await queue.setTableState(tableId: 'table-1', state: 'cleaning');
      online = true;
      await engine.run();

      expect(transport.calls, ['setTableState:table-1:cleaning']);
    });

    test('manager ops do not orphan each other when one is refused', () async {
      // A rejected 86 must not poison an unrelated table change: only a dead
      // *create* orphans what follows, and these share no order.
      final h = _harness();
      h.transport.failures.add(
        const TransportRejected('not authorized to change stock'),
      );

      final refused = await h.queue.setItem86(itemId: 'item-1', is86: true);
      final ok = await h.queue.setTableState(
        tableId: 'table-1',
        state: 'cleaning',
      );

      expect(refused.isRejected, isTrue);
      expect(refused.error, 'not authorized to change stock');
      expect(ok.synced, isTrue);
      expect(ok.isRejected, isFalse);
    });

    test('a refused op keeps its reason for the waiter to read', () async {
      final h = _harness();
      h.transport.failures.add(
        const TransportRejected('table A1 still has an open order'),
      );

      await h.queue.setTableState(tableId: 'table-1', state: 'free');

      final dead = await h.queue.deadEntries();
      expect(dead.single.kind, OutboxKind.tableState);
      expect(dead.single.lastError, 'table A1 still has an open order');
    });
  });

  group('stock counts', () {
    ({MemoryOutboxStore store, FakeTransport transport, OrderQueue queue})
    harness({required bool Function() online}) {
      final store = MemoryOutboxStore();
      final transport = FakeTransport();
      final engine = ReplayEngine(
        store: store,
        transport: transport,
        isOnline: () async => online(),
      );
      return (
        store: store,
        transport: transport,
        queue: OrderQueue(store: store, engine: engine, tenantId: 'tenant-1'),
      );
    }

    test('a count made in a walk-in reaches the server later', () async {
      var online = false;
      final h = harness(online: () => online);

      final outcome = await h.queue.setCountActual(
        countItemId: 'line-1',
        actual: 12,
      );
      expect(outcome.synced, isFalse, reason: 'no coverage in the walk-in');
      expect(h.transport.calls, isEmpty);

      online = true;
      await h.queue.setCountActual(countItemId: 'line-2', actual: 3.5);

      expect(h.transport.calls, [
        'setCountActual:line-1:12.0',
        'setCountActual:line-2:3.5',
      ]);
      expect(await h.queue.pendingCount(), 0);
    });

    test(
      'recounting the same shelf replaces the queued value, never queues twice',
      () async {
        var online = false;
        final h = harness(online: () => online);

        await h.queue.setCountActual(countItemId: 'line-1', actual: 9);
        await h.queue.setCountActual(countItemId: 'line-1', actual: 11);
        await h.queue.setCountActual(countItemId: 'line-1', actual: 10);

        // One shelf, one owed write — not three. A store keeper who miscounts
        // twice must not see three pending writes for one shelf.
        expect(await h.queue.pendingCount(), 1);

        online = true;
        await h.queue.setCountActual(countItemId: 'line-1', actual: 10);

        // And only the last number reaches the server.
        expect(h.transport.calls, ['setCountActual:line-1:10.0']);
      },
    );

    test(
      'replaying an already-sent count is harmless — it is absolute',
      () async {
        final h = harness(online: () => true);

        await h.queue.setCountActual(countItemId: 'line-1', actual: 4);
        // Simulate the app dying between the call and the row being marked done:
        // the row goes back to inflight and is replayed under the same key.
        final row = (await h.store.all()).single;
        await h.store.markInflight(row.id);
        await h.queue.setCountActual(countItemId: 'line-9', actual: 1);

        expect(h.transport.calls, [
          'setCountActual:line-1:4.0',
          'setCountActual:line-1:4.0',
          'setCountActual:line-9:1.0',
        ]);
        // Writing 4 twice leaves 4. That is the whole reason a count may queue
        // and an adjustment may not.
      },
    );

    test('a refused count dies with its reason, and says which line', () async {
      final h = harness(online: () => true);
      h.transport.failures.add(
        const TransportRejected('this count was already posted'),
      );

      final outcome = await h.queue.setCountActual(
        countItemId: 'line-1',
        actual: 7,
      );

      expect(outcome.error, 'this count was already posted');
      final dead = await h.queue.deadEntries();
      expect(dead.single.kind, OutboxKind.stockCount);
      expect(dead.single.orderRef, 'count_item:line-1');
    });
  });
}
