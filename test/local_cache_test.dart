import 'package:extrahelper/data/local/database.dart';
import 'package:extrahelper/data/local/drift_outbox_store.dart';
import 'package:extrahelper/data/local/identity_cache.dart';
import 'package:extrahelper/data/local/pos_cache.dart';
import 'package:extrahelper/data/supabase/inventory_repository.dart';
import 'package:extrahelper/data/supabase/tenant_repository.dart';
import 'package:extrahelper/data/sync/outbox.dart';
import 'package:extrahelper/data/sync/replay_engine.dart';
import 'package:extrahelper/data/sync/transport.dart';
import 'package:extrahelper/features/pos/models.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingTransport implements OutboxTransport {
  final List<String> calls = [];
  int createdOrders = 0;
  final Map<String, String> _byKey = {};

  @override
  Future<String> placeOrder({
    required String idempotencyKey,
    required Map<String, dynamic> payload,
  }) async {
    calls.add('placeOrder:$idempotencyKey');
    final existing = _byKey[idempotencyKey];
    if (existing != null) return existing;
    createdOrders++;
    return _byKey[idempotencyKey] = 'order-$createdOrders';
  }

  @override
  Future<void> addItem({
    required String orderId,
    required Map<String, dynamic> payload,
  }) async => calls.add('addItem:$orderId');

  @override
  Future<void> voidLine({
    required String orderItemId,
    required String reason,
  }) async => calls.add('voidLine:$orderItemId');

  @override
  Future<void> fire(String orderId) async => calls.add('fire:$orderId');

  @override
  Future<void> setItem86({required String itemId, required bool is86}) async =>
      calls.add('setItem86:$itemId:$is86');

  @override
  Future<void> setTableState({
    required String tableId,
    required String state,
  }) async => calls.add('setTableState:$tableId:$state');

  @override
  Future<void> setCountActual({
    required String countItemId,
    required double actual,
  }) async => calls.add('setCountActual:$countItemId:$actual');

  @override
  Future<void> setKotLineStatus({
    required String kotItemId,
    required String status,
  }) async => calls.add('setKotLineStatus:$kotItemId:$status');

  @override
  Future<void> setKotStatus({
    required String kotId,
    required String status,
  }) async => calls.add('setKotStatus:$kotId:$status');
  @override
  Future<void> markOrderServed(String orderId) async =>
      calls.add('markOrderServed:$orderId');
}

PosMenuItem _item(
  String id, {
  List<PosVariant> variants = const [],
  List<PosModifier> modifiers = const [],
}) => PosMenuItem(
  id: id,
  name: 'Dish $id',
  basePriceCents: 38000,
  categoryId: 'cat-1',
  is86: false,
  isVeg: true,
  variants: variants,
  modifiers: modifiers,
);

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.memory());
  tearDown(() => db.close());

  group('outbox on disk', () {
    test('a double enqueue under one key stays one row', () async {
      final store = DriftOutboxStore(db);
      final payload = {
        'order_type': 'dine_in',
        'items': <dynamic>[],
        'fire': false,
      };

      final a = await store.enqueue(
        tenantId: 't1',
        kind: OutboxKind.order,
        orderRef: 'draft:1',
        payload: payload,
        idempotencyKey: 'key-1',
      );
      final b = await store.enqueue(
        tenantId: 't1',
        kind: OutboxKind.order,
        orderRef: 'draft:1',
        payload: payload,
        idempotencyKey: 'key-1',
      );

      expect(a.id, b.id);
      expect((await store.all()).length, 1);
    });

    test('payload, state and attempts survive a round trip', () async {
      final store = DriftOutboxStore(db);
      final entry = await store.enqueue(
        tenantId: 't1',
        kind: OutboxKind.amendAdd,
        orderRef: 'order-9',
        payload: {
          'item_id': 'x',
          'qty': 2,
          'modifier_ids': ['m1', 'm2'],
        },
        idempotencyKey: 'key-2',
      );

      await store.markInflight(entry.id);
      await store.reschedule(entry.id, 'Network unreachable');

      final read = (await store.byId(entry.id))!;
      expect(read.kind, OutboxKind.amendAdd);
      expect(read.payload['qty'], 2);
      expect(read.payload['modifier_ids'], ['m1', 'm2']);
      expect(read.attempts, 1);
      expect(read.state, OutboxState.pending);
      expect(read.lastError, 'Network unreachable');
    });

    test('a persisted inflight row is replayed under the same key', () async {
      final store = DriftOutboxStore(db);
      final transport = _RecordingTransport();
      final entry = await store.enqueue(
        tenantId: 't1',
        kind: OutboxKind.order,
        orderRef: 'draft:z',
        payload: {'order_type': 'dine_in', 'items': <dynamic>[], 'fire': true},
        idempotencyKey: 'key-crash',
      );
      // The state a kill mid-call leaves on disk.
      await store.markInflight(entry.id);

      // "Restart": a brand-new engine over the same file.
      await ReplayEngine(
        store: store,
        transport: transport,
        isOnline: () async => true,
      ).run();

      expect(transport.calls, ['placeOrder:key-crash', 'fire:order-1']);
      expect(transport.createdOrders, 1);
      expect((await store.byId(entry.id))!.state, OutboxState.done);
      expect((await store.byId(entry.id))!.orderRef, 'order-1');
    });

    test('remap rewrites every entry queued behind the draft', () async {
      final store = DriftOutboxStore(db);
      await store.enqueue(
        tenantId: 't1',
        kind: OutboxKind.amendAdd,
        orderRef: 'draft:q',
        payload: {'item_id': 'a'},
        idempotencyKey: 'k1',
      );
      await store.enqueue(
        tenantId: 't1',
        kind: OutboxKind.fire,
        orderRef: 'draft:q',
        payload: const {},
        idempotencyKey: 'k2',
      );

      await store.remapOrderRef('draft:q', 'order-77');

      expect((await store.all()).map((e) => e.orderRef), [
        'order-77',
        'order-77',
      ]);
    });
  });

  group('menu cache', () {
    test(
      'a saved menu reads back whole, variants sorted, add-ons linked',
      () async {
        final cache = PosCache(db);
        await cache.adoptTenant('t1');
        await cache.saveMenu('t1', [
          _item(
            'i1',
            variants: [
              const PosVariant(id: 'v2', name: 'KG', priceDeltaCents: 130000),
              const PosVariant(id: 'v1', name: 'Half', priceDeltaCents: 0),
            ],
            modifiers: [
              const PosModifier(
                id: 'm1',
                name: 'Extra spicy',
                priceCents: 5000,
              ),
            ],
          ),
          _item('i2'),
        ]);

        final menu = await cache.menu('t1');
        expect(menu.map((i) => i.id), ['i1', 'i2']);
        final first = menu.first;
        expect(first.variants.map((v) => v.name), ['Half', 'KG']);
        expect(first.modifiers.single.name, 'Extra spicy');
        expect(first.priceRange, (min: 38000, max: 168000));
        expect(menu.last.modifiers, isEmpty);
      },
    );

    test(
      'the owner-chosen order survives the cache, price order does not',
      () async {
        // Half costs less than KG but the owner put it last, so price order is
        // exactly the wrong answer here.
        final cache = PosCache(db);
        await cache.adoptTenant('t1');
        await cache.saveMenu('t1', [
          _item(
            'i1',
            variants: const [
              PosVariant(id: 'v1', name: 'Half', priceDeltaCents: 0, sort: 2),
              PosVariant(
                id: 'v2',
                name: 'KG',
                priceDeltaCents: 130000,
                sort: 1,
              ),
            ],
          ),
        ]);

        final menu = await cache.menu('t1');
        expect(menu.single.variants.map((v) => v.name), ['KG', 'Half']);
      },
    );

    test('the board and floors read back from cache alone', () async {
      final cache = PosCache(db);
      await cache.adoptTenant('t1');
      await cache.saveFloors('t1', [
        const PosFloor(id: 'f1', name: 'Ground Floor', sort: 0),
      ]);
      await cache.saveTables('t1', [
        const PosTable(
          id: 'tb1',
          label: 'C1',
          capacity: 4,
          state: 'occupied',
          floorId: 'f1',
        ),
      ]);

      expect((await cache.floors('t1')).single.name, 'Ground Floor');
      final table = (await cache.tables('t1')).single;
      expect(table.label, 'C1');
      expect(table.state, 'occupied');

      await cache.upsertTable('t1', table.copyWith(state: 'bill_requested'));
      expect((await cache.tables('t1')).single.state, 'bill_requested');
    });

    test(
      'switching tenant wipes the cache — never one menu under another name',
      () async {
        final cache = PosCache(db);
        await cache.adoptTenant('t1');
        await cache.saveMenu('t1', [_item('i1')]);
        await cache.saveCategories('t1', [
          const PosCategory(id: 'c1', name: 'Drinks', sort: 0),
        ]);
        expect(await cache.menu('t1'), isNotEmpty);

        await cache.adoptTenant('t2');

        expect(await cache.menu('t1'), isEmpty);
        expect(await cache.categories('t1'), isEmpty);
        expect(await cache.menu('t2'), isEmpty);
        expect(await cache.fetchedAt('t1'), isNull);
      },
    );

    test('re-adopting the same tenant keeps the cache', () async {
      final cache = PosCache(db);
      await cache.adoptTenant('t1');
      await cache.saveMenu('t1', [_item('i1')]);

      await cache.adoptTenant('t1');

      expect(await cache.menu('t1'), hasLength(1));
      expect(await cache.fetchedAt('t1'), isNotNull);
    });
  });

  group('identity cache', () {
    test('memberships survive a cold start, in order', () async {
      final cache = IdentityCache(db);
      await cache.saveMemberships(const [
        Membership(
          tenantId: 't1',
          name: 'The Sekuwa Station',
          slug: 'sekuwa',
          role: 'owner',
          currency: 'NPR',
          timezone: 'Asia/Kathmandu',
        ),
        Membership(
          tenantId: 't2',
          name: 'Second Place',
          slug: 'second',
          role: 'waiter',
          currency: 'USD',
          timezone: 'UTC',
        ),
      ]);

      final read = await cache.memberships();
      expect(read.map((m) => m.tenantId), ['t1', 't2']);
      expect(read.first.currency, 'NPR', reason: 'never a hardcoded currency');
      expect(read.first.role, 'owner');
    });

    test('permissions are per tenant and survive a cold start', () async {
      final cache = IdentityCache(db);
      await cache.savePermissions('t1', {'order.create', 'order.fire'});
      await cache.savePermissions('t2', {'kds.view'});

      expect(await cache.permissions('t1'), {'order.create', 'order.fire'});
      expect(await cache.permissions('t2'), {'kds.view'});
    });

    test('signing out clears identity — the next user sees nothing', () async {
      final cache = IdentityCache(db);
      await cache.saveMemberships(const [
        Membership(
          tenantId: 't1',
          name: 'A',
          slug: 'a',
          role: 'owner',
          currency: 'NPR',
          timezone: 'Asia/Kathmandu',
        ),
      ]);
      await cache.savePermissions('t1', {'order.create'});

      await cache.clear();

      expect(await cache.memberships(), isEmpty);
      expect(await cache.permissions('t1'), isEmpty);
    });

    test(
      'switching tenant wipes permissions with the rest of the cache',
      () async {
        final cache = IdentityCache(db);
        final pos = PosCache(db);
        await pos.adoptTenant('t1');
        await cache.savePermissions('t1', {'order.create'});

        await pos.adoptTenant('t2');

        expect(await cache.permissions('t1'), isEmpty);
      },
    );
  });

  group('first run', () {
    test(
      'adopting a tenant keeps permissions cached before the first stamp',
      () async {
        // The shell caches permissions as soon as the user resolves; the POS then
        // mounts and adopts the tenant. On a fresh install `cache_meta` is still
        // empty at that point — a blanket wipe deleted the permissions and the
        // next cold start with no coverage rendered "No ordering access".
        final identity = IdentityCache(db);
        final pos = PosCache(db);

        await identity.savePermissions('t1', {'order.create', 'order.fire'});
        await pos.adoptTenant('t1');

        expect(await identity.permissions('t1'), {
          'order.create',
          'order.fire',
        });
      },
    );

    test('adopting still drops another tenant rows, stamped or not', () async {
      final identity = IdentityCache(db);
      final pos = PosCache(db);

      await identity.savePermissions('t1', {'order.create'});
      await pos.saveMenu('t1', [_item('i1')]);

      await pos.adoptTenant('t2');

      expect(await identity.permissions('t1'), isEmpty);
      expect(await pos.menu('t1'), isEmpty);
      expect(await pos.fetchedAt('t1'), isNull);
    });
  });

  group('housekeeping', () {
    test('pruning drops old done rows and keeps dead ones', () async {
      final store = DriftOutboxStore(db);

      final done = await store.enqueue(
        tenantId: 't1',
        kind: OutboxKind.order,
        orderRef: 'order-1',
        payload: const {},
        idempotencyKey: 'k-done',
      );
      final dead = await store.enqueue(
        tenantId: 't1',
        kind: OutboxKind.amendAdd,
        orderRef: 'order-1',
        payload: const {},
        idempotencyKey: 'k-dead',
      );
      final fresh = await store.enqueue(
        tenantId: 't1',
        kind: OutboxKind.fire,
        orderRef: 'order-1',
        payload: const {},
        idempotencyKey: 'k-fresh',
      );
      await store.markDone(done.id);
      await store.markDead(dead.id, "Momo is 86'd.");
      await store.markDone(fresh.id);

      // Everything enqueued just now, so a cutoff in the future catches the
      // done rows and nothing else.
      final removed = await store.pruneSettled(
        DateTime.now().add(const Duration(days: 1)),
      );

      expect(removed, 2);
      final left = await store.all();
      expect(
        left.single.id,
        dead.id,
        reason: 'a dead row still needs a person',
      );
      expect(left.single.lastError, "Momo is 86'd.");
    });

    test('a cutoff before the rows keeps everything', () async {
      final store = DriftOutboxStore(db);
      final row = await store.enqueue(
        tenantId: 't1',
        kind: OutboxKind.order,
        orderRef: 'order-1',
        payload: const {},
        idempotencyKey: 'k1',
      );
      await store.markDone(row.id);

      expect(
        await store.pruneSettled(
          DateTime.now().subtract(const Duration(days: 7)),
        ),
        0,
      );
      expect(await store.all(), hasLength(1));
    });
  });

  group('stock cache', () {
    test('an 86 from Realtime survives a cold start', () async {
      final cache = PosCache(db);
      await cache.adoptTenant('t1');
      await cache.saveMenu('t1', [_item('i1'), _item('i2')]);

      await cache.setCachedItem86('t1', 'i1', true);

      final menu = await cache.menu('t1');
      expect(menu.firstWhere((i) => i.id == 'i1').is86, isTrue);
      expect(menu.firstWhere((i) => i.id == 'i2').is86, isFalse);
    });

    test('one tenant stock flag cannot touch another', () async {
      final cache = PosCache(db);
      await cache.saveMenu('t1', [_item('i1')]);
      await cache.saveMenu('t2', [_item('i1')]);

      await cache.setCachedItem86('t1', 'i1', true);

      expect((await cache.menu('t1')).single.is86, isTrue);
      expect((await cache.menu('t2')).single.is86, isFalse);
    });
  });

  group('store room cache', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase.memory());
    tearDown(() => db.close());

    InventoryItem inv(String id, {String name = 'Flour', double qty = 8}) =>
        InventoryItem(
          id: id,
          name: name,
          uom: 'kg',
          currentQty: qty,
          reorderLevel: 10,
          costCents: 12000,
          barcode: '590$id',
        );

    test('a count in a walk-in reads its worklist from cache alone', () async {
      final cache = PosCache(db);
      await cache.saveInventory('t1', [
        inv('i1', name: 'Flour'),
        inv('i2', name: 'Rice', qty: 40),
      ]);

      final rows = await cache.inventory('t1');
      expect(rows.map((r) => r.name), ['Flour', 'Rice']);
      // The low flag has to survive the round trip: it is the reason the list
      // is sorted the way it is.
      expect(rows.firstWhere((r) => r.name == 'Flour').isLow, isTrue);
      expect(rows.firstWhere((r) => r.name == 'Rice').isLow, isFalse);
      expect(rows.first.barcode, '590i1');
    });

    test(
      "switching tenant takes the other restaurant's stock with it",
      () async {
        final cache = PosCache(db);
        await cache.adoptTenant('t1');
        await cache.saveInventory('t1', [inv('i1')]);
        expect(await cache.inventory('t1'), isNotEmpty);

        await cache.adoptTenant('t2');

        expect(await cache.inventory('t1'), isEmpty);
        expect(await cache.inventory('t2'), isEmpty);
      },
    );

    test('one restaurant cannot see another quantities', () async {
      final cache = PosCache(db);
      await cache.saveInventory('t1', [inv('i1', qty: 8)]);
      await cache.saveInventory('t2', [inv('i1', qty: 99)]);

      expect((await cache.inventory('t1')).single.currentQty, 8);
      expect((await cache.inventory('t2')).single.currentQty, 99);
    });
  });
}
