import 'package:extrahelper/data/supabase/kds_repository.dart';
import 'package:extrahelper/data/sync/order_queue.dart';
import 'package:extrahelper/data/sync/outbox.dart';
import 'package:extrahelper/data/sync/replay_engine.dart';
import 'package:extrahelper/data/sync/transport.dart';
import 'package:extrahelper/features/kds/kds_constants.dart';
import 'package:flutter_test/flutter_test.dart';

/// The kitchen board's two rules that are worth testing without an emulator:
/// what a ticket's status is derived from, and how its writes queue.

class _Transport implements OutboxTransport {
  final List<String> calls = [];
  Object? failWith;

  void _maybeThrow() {
    final f = failWith;
    if (f != null) throw f;
  }

  @override
  Future<void> setKotLineStatus({
    required String kotItemId,
    required String status,
  }) async {
    calls.add('line:$kotItemId:$status');
    _maybeThrow();
  }

  @override
  Future<void> setKotStatus({
    required String kotId,
    required String status,
  }) async {
    calls.add('ticket:$kotId:$status');
    _maybeThrow();
  }

  @override
  Future<void> markOrderServed(String orderId) async {
    calls.add('served:$orderId');
    _maybeThrow();
  }

  @override
  Future<String> placeOrder({
    required String idempotencyKey,
    required Map<String, dynamic> payload,
  }) async => 'unused';

  @override
  Future<void> addItem({
    required String orderId,
    required Map<String, dynamic> payload,
  }) async {}

  @override
  Future<void> voidLine({
    required String orderItemId,
    required String reason,
  }) async {}

  @override
  Future<void> fire(String orderId) async {}

  @override
  Future<void> setItem86({required String itemId, required bool is86}) async {}

  @override
  Future<void> setTableState({
    required String tableId,
    required String state,
  }) async {}

  @override
  Future<void> setCountActual({
    required String countItemId,
    required double actual,
  }) async {}
}

({OrderQueue queue, _Transport transport, MemoryOutboxStore store}) _harness({
  bool online = true,
}) {
  final store = MemoryOutboxStore();
  final transport = _Transport();
  final queue = OrderQueue(
    store: store,
    engine: ReplayEngine(
      store: store,
      transport: transport,
      isOnline: () async => online,
    ),
    tenantId: 't1',
  );
  return (queue: queue, transport: transport, store: store);
}

KdsLine _line(
  String id,
  KotStatus status, {
  bool isVoid = false,
  int qty = 1,
}) => KdsLine(
  id: id,
  orderItemId: 'oi-$id',
  name: 'Dish $id',
  qty: qty,
  status: status,
  isVoid: isVoid,
);

KdsTicket _ticket(
  List<KdsLine> lines, {
  KotStatus status = KotStatus.newTicket,
  String? orderStatus,
}) => KdsTicket(
  id: 'k1',
  status: status,
  createdAt: DateTime(2026, 7, 31, 19),
  orderId: 'o1',
  lines: lines,
  station: 'Grill',
  printed: false,
  orderStatus: orderStatus,
);

void main() {
  group('a ticket is finished when the kitchen OR the till says so', () {
    test('a bumped ticket is done', () {
      final t = _ticket(
        [_line('a', KotStatus.served)],
        status: KotStatus.served,
        orderStatus: 'served',
      );
      expect(t.isCompleted, isTrue);
    });

    test('a ready ticket on a closed order leaves the pass', () {
      // The live defect this fixes: the food went out, the guest paid, and the
      // ticket sat on the board forever because nobody bumped it. A board with
      // permanent residents is a board cooks stop reading.
      final t = _ticket(
        [_line('a', KotStatus.ready)],
        status: KotStatus.ready,
        orderStatus: 'closed',
      );
      expect(t.isCompleted, isTrue);
    });

    test('a new ticket on a billed order is work in hand, not history', () {
      // `billed` says a bill was printed, not that anyone paid it. A table that
      // asks for the bill and then orders one more round fires a real ticket
      // onto an order that stays `billed` — and this predicate is what decides
      // whether the kitchen ever sees it. Treating it as finished charged the
      // guest for food nobody cooked.
      final t = _ticket([
        _line('a', KotStatus.newTicket),
      ], orderStatus: 'billed');
      expect(t.isCompleted, isFalse);
    });

    test('closed and cancelled orders take their tickets with them', () {
      for (final status in ['closed', 'cancelled']) {
        final t = _ticket([
          _line('a', KotStatus.newTicket),
        ], orderStatus: status);
        expect(t.isCompleted, isTrue, reason: status);
      }
    });

    test('a new ticket on a live order is still work in hand', () {
      final t = _ticket([
        _line('a', KotStatus.newTicket),
      ], orderStatus: 'placed');
      expect(t.isCompleted, isFalse);
    });

    test('an order-finished ticket is not offered for recall', () {
      // It left the board because the guest paid and went, not because a cook
      // bumped it. `recall_kot` would put a ticket for an empty table back on
      // the pass — and the query has no date bound on `ready`, so it would sit
      // on the recall strip for the life of the restaurant.
      final billed = _ticket(
        [_line('a', KotStatus.ready)],
        status: KotStatus.ready,
        orderStatus: 'closed',
      );
      final bumped = _ticket(
        [_line('a', KotStatus.served)],
        status: KotStatus.served,
        orderStatus: 'served',
      );

      expect(billed.isCompleted, isTrue);
      expect(
        billed.status == KotStatus.served,
        isFalse,
        reason: 'so the recall strip must not pick it up',
      );
      expect(bumped.status == KotStatus.served, isTrue);
    });

    test('an order status nobody sent does not finish the ticket', () {
      // Absent is not "done" — a null from an older row must leave the ticket
      // on the board, where a cook can see it, rather than hiding it.
      final t = _ticket([_line('a', KotStatus.preparing)]);
      expect(t.isCompleted, isFalse);
    });
  });

  group('a ticket is its least-advanced live line', () {
    test('one dish plated, one still cooking, ticket stays cooking', () {
      final t = _ticket([
        _line('a', KotStatus.ready),
        _line('b', KotStatus.preparing),
      ]);
      expect(t.derived, KotStatus.preparing);
    });

    test('every dish ready makes the ticket ready', () {
      final t = _ticket([
        _line('a', KotStatus.ready),
        _line('b', KotStatus.ready),
      ]);
      expect(t.derived, KotStatus.ready);
    });

    test('a cancelled dish does not hold the ticket back', () {
      final t = _ticket([
        _line('a', KotStatus.ready),
        _line('b', KotStatus.newTicket, isVoid: true),
      ]);
      expect(t.derived, KotStatus.ready);
    });

    test('a fully cancelled ticket keeps the status it had', () {
      final t = _ticket([
        _line('a', KotStatus.newTicket, isVoid: true),
      ], status: KotStatus.preparing);
      // Deriving "served" from nothing would declare a cancelled ticket done.
      expect(t.derived, KotStatus.preparing);
    });

    test('recalled ranks with cooking, not with new', () {
      final t = _ticket([
        _line('a', KotStatus.recalled),
        _line('b', KotStatus.ready),
      ]);
      expect(t.derived, KotStatus.preparing);
    });
  });

  group('the flow', () {
    test('advances new → cooking → ready → served, then stops', () {
      expect(nextKotStatus(KotStatus.newTicket), KotStatus.preparing);
      expect(nextKotStatus(KotStatus.preparing), KotStatus.ready);
      expect(nextKotStatus(KotStatus.ready), KotStatus.served);
      expect(nextKotStatus(KotStatus.served), isNull);
    });

    test('a recalled ticket rejoins at ready rather than stranding', () {
      // It is back on the pass and being cooked; the next thing that happens to
      // it is that it is plated again.
      expect(nextKotStatus(KotStatus.recalled), KotStatus.ready);
    });

    test('every status a cook can see has a label and an icon', () {
      for (final status in KotStatus.values) {
        final meta = kotStatusMeta[status];
        expect(meta, isNotNull, reason: '$status has no metadata');
        expect(meta!.label, isNotEmpty);
        expect(meta.hint, isNotEmpty);
      }
    });
  });

  group('kitchen writes queue', () {
    test('a dish status reaches the server when there is coverage', () async {
      final h = _harness();
      final outcome = await h.queue.setKotLineStatus(
        kotItemId: 'ki-1',
        status: 'ready',
      );
      expect(outcome.synced, isTrue);
      expect(h.transport.calls, ['line:ki-1:ready']);
    });

    test('with no coverage it is durable, not lost', () async {
      final h = _harness(online: false);
      final outcome = await h.queue.setKotLineStatus(
        kotItemId: 'ki-1',
        status: 'ready',
      );
      expect(outcome.synced, isFalse, reason: 'queued, not sent');
      expect(h.transport.calls, isEmpty);
      expect((await h.store.due()).length, 1);
    });

    test(
      'correcting a mis-tap replaces the queued write, never adds one',
      () async {
        final h = _harness(online: false);
        await h.queue.setKotLineStatus(kotItemId: 'ki-1', status: 'ready');
        await h.queue.setKotLineStatus(kotItemId: 'ki-1', status: 'preparing');

        final due = await h.store.due();
        expect(due.length, 1, reason: 'one dish owes the server one write');
        expect(due.single.payload['status'], 'preparing');
      },
    );

    test('two different dishes owe two writes', () async {
      final h = _harness(online: false);
      await h.queue.setKotLineStatus(kotItemId: 'ki-1', status: 'ready');
      await h.queue.setKotLineStatus(kotItemId: 'ki-2', status: 'ready');
      expect((await h.store.due()).length, 2);
    });

    test('a recall is a ticket status, queued like any other', () async {
      final h = _harness();
      await h.queue.setKotStatus(kotId: 'k-1', status: 'recalled');
      expect(h.transport.calls, ['ticket:k-1:recalled']);
    });

    test('delivered queues and lands under the order id', () async {
      final h = _harness();
      await h.queue.markOrderServed('o-1');
      expect(h.transport.calls, ['served:o-1']);
    });

    test('a refusal dies immediately with the reason kept', () async {
      final h = _harness();
      h.transport.failWith = const TransportRejected(
        'not authorized to move a ticket',
      );

      final outcome = await h.queue.setKotStatus(kotId: 'k-1', status: 'ready');
      expect(outcome.isRejected, isTrue);
      expect(outcome.error, contains('not authorized'));

      final row = (await h.store.all()).single;
      expect(row.state, OutboxState.dead);
      expect(row.attempts, 0, reason: 'a considered no is not retried');
    });

    test('a dropped connection is retried, not counted as a refusal', () async {
      final h = _harness();
      h.transport.failWith = const TransportTransient('socket closed');

      final outcome = await h.queue.setKotLineStatus(
        kotItemId: 'ki-1',
        status: 'ready',
      );
      expect(outcome.isRejected, isFalse);

      final row = (await h.store.all()).single;
      expect(row.state, OutboxState.pending);
      expect(row.attempts, 1);
    });
  });
}
