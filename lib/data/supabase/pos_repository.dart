import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../features/pos/models.dart';
import 'supabase_providers.dart';

/// Failure with a message a waiter can act on. The repository boundary never
/// leaks `PostgrestException`.
class PosFailure implements Exception {
  const PosFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The write never got an answer — socket, timeout, airplane mode.
///
/// Separate from a plain [PosFailure] because the outbox must treat the two
/// differently (`PLANNING.md` §2, rule 3): a server *reject* is final, a
/// transient failure is still owed. Conflating them is how a real order gets
/// silently dropped.
class PosTransientFailure extends PosFailure {
  const PosTransientFailure(super.message);
}

/// Reads and writes for the POS.
///
/// Trusted logic stays in SQL and is called by RPC — `place_staff_order` to
/// create, `amend_order_add_item` to add to an existing order,
/// `void_order_item` to remove a fired line, `fire_order` to send to the
/// kitchen. Plain reads go through PostgREST under RLS, **plus an explicit
/// tenant filter** as defense in depth (rule 2).
class PosRepository {
  const PosRepository(this._client, this._tenantId);

  final SupabaseClient _client;
  final String _tenantId;

  static const _uuid = Uuid();

  // --- Menu ----------------------------------------------------------------

  Future<List<PosCategory>> categories() async {
    final rows = await _client
        .from('menu_categories')
        .select('id, name, sort')
        .eq('tenant_id', _tenantId)
        .eq('is_active', true)
        .order('sort');
    return rows
        .map(
          (r) => PosCategory(
            id: r['id'] as String,
            name: (r['name'] as String?) ?? '',
            sort: (r['sort'] as int?) ?? 0,
          ),
        )
        .toList();
  }

  /// Menu with variants and **only the add-ons linked to each item**.
  ///
  /// The link matters: the server rejects a modifier that isn't in
  /// `item_modifiers` for that item, so offering a tenant-wide list would build
  /// a picker whose choices get refused ("Extra cheese" on a beer).
  Future<List<PosMenuItem>> menu() async {
    final rows = await _client
        .from('menu_items')
        .select(
          'id, name, base_price_cents, category_id, is_86, is_veg, image_url, '
          'item_variants(id, name, price_delta_cents, sort), '
          'item_modifiers(modifiers(id, name, price_cents))',
        )
        .eq('tenant_id', _tenantId)
        .eq('is_active', true)
        .order('name');

    return rows.map((r) {
      final variants =
          (r['item_variants'] as List<dynamic>? ?? const [])
              .map((v) => PosVariant.fromRow(v as Map<String, dynamic>))
              .toList()
            ..sort((a, b) {
              final bySort = a.sort.compareTo(b.sort);
              return bySort != 0
                  ? bySort
                  : a.priceDeltaCents.compareTo(b.priceDeltaCents);
            });

      final modifiers = (r['item_modifiers'] as List<dynamic>? ?? const [])
          .map((l) => (l as Map<String, dynamic>)['modifiers'])
          .whereType<Map<String, dynamic>>()
          .map(PosModifier.fromRow)
          .toList();

      return PosMenuItem(
        id: r['id'] as String,
        name: (r['name'] as String?) ?? '',
        basePriceCents: (r['base_price_cents'] as int?) ?? 0,
        categoryId: r['category_id'] as String?,
        is86: (r['is_86'] as bool?) ?? false,
        imageUrl: r['image_url'] as String?,
        isVeg: r['is_veg'] as bool?,
        variants: variants,
        modifiers: modifiers,
      );
    }).toList();
  }

  // --- Floor ---------------------------------------------------------------

  Future<List<PosFloor>> floors() async {
    final rows = await _client
        .from('floors')
        .select('id, name, sort')
        .eq('tenant_id', _tenantId)
        .order('sort');
    return rows
        .map(
          (r) => PosFloor(
            id: r['id'] as String,
            name: (r['name'] as String?) ?? '',
            sort: (r['sort'] as int?) ?? 0,
          ),
        )
        .toList();
  }

  Future<List<PosTable>> tables() async {
    final rows = await _client
        .from('restaurant_tables')
        .select('id, label, capacity, state, floor_id, current_order_id')
        .eq('tenant_id', _tenantId)
        .order('label');
    return rows.map((r) => PosTable.fromRow(r)).toList();
  }

  // --- Orders --------------------------------------------------------------

  /// The bill embed carries `status`, not just the id: since the amend RPCs
  /// started accepting items on a `billed` order whose bill is still `open`,
  /// the order's own status no longer says whether it can be added to. The
  /// `!orders_bill_id_fkey` hint is load-bearing for the same reason it is on
  /// [completedSelect] — more than one path reaches `bills`, and PostgREST
  /// refuses the embed rather than guessing.
  static const _orderSelect =
      'id, status, order_type, created_at, table_id, guests, bill_id, '
      'pinned_at, '
      'restaurant_tables!orders_table_id_fkey(label), '
      'bills!orders_bill_id_fkey(id, status), '
      'order_items(id, name_snapshot, qty, unit_price_cents, status, is_void, notes, '
      'order_item_modifiers(name_snapshot))';

  /// Orders still on the floor. Closed and cancelled ones are history.
  ///
  /// Pinned first, then newest — the same order the web board uses. A pin is
  /// how a waiter keeps the table they are mid-service on from sliding down a
  /// list that reorders itself every time anyone else fires an order.
  Future<List<PosOrder>> activeOrders() async {
    final rows = await _client
        .from('orders')
        .select(_orderSelect)
        .eq('tenant_id', _tenantId)
        .not('status', 'in', '("closed","cancelled","billed")')
        .order('pinned_at', ascending: false, nullsFirst: false)
        .order('created_at', ascending: false);
    return rows.map((r) => PosOrder.fromRow(r)).toList();
  }

  /// The same select the web's Completed tab uses, down to the FK hints.
  ///
  /// The hints are load-bearing: `orders` reaches `restaurant_tables` and
  /// `bills` by more than one path, and without naming the constraint PostgREST
  /// refuses the embed rather than guessing.
  ///
  /// Public because the day-close report reads the same rows over a different
  /// window — one shape for "a finished order", not two that drift apart.
  static const completedSelect =
      'id, order_type, status, created_at, guests, table_id, bill_id, '
      'restaurant_tables!orders_table_id_fkey(label), '
      'order_items(id, name_snapshot, qty, unit_price_cents, is_void, notes), '
      'bills!orders_bill_id_fkey(id, status, total_cents, payments(method, amount_cents, status))';

  /// Where this restaurant's trading day began, in its own timezone.
  ///
  /// Asked of the server rather than computed here — `package:intl` has no IANA
  /// timezone database, and a boundary that decides which orders a waiter can
  /// see must not be a second implementation. See the `tenant_day_start`
  /// migration.
  Future<DateTime> tenantDayStart() async {
    try {
      final at = await _client.rpc<dynamic>(
        'tenant_day_start',
        params: {'_tenant': _tenantId},
      );
      final parsed = DateTime.tryParse(at as String? ?? '');
      if (parsed != null) return parsed;
    } on PostgrestException catch (e) {
      throw PosFailure(_friendly(e.message));
    } catch (_) {
      throw const PosTransientFailure("Couldn't load today's orders.");
    }
    throw const PosTransientFailure("Couldn't work out when today began.");
  }

  /// Today's finished orders — billed, closed and cancelled.
  ///
  /// Today only, and capped: a busy till closes a few hundred orders a day, and
  /// a tenant that hits the cap wants the reports on the web app, not a bigger
  /// query on a phone.
  Future<List<PosCompletedOrder>> completedOrders({int limit = 300}) async {
    final dayStart = await tenantDayStart();
    try {
      final rows = await _client
          .from('orders')
          .select(completedSelect)
          .eq('tenant_id', _tenantId)
          .inFilter('status', const ['billed', 'closed', 'cancelled'])
          .gte('created_at', dayStart.toUtc().toIso8601String())
          .order('created_at', ascending: false)
          .limit(limit);
      return rows.map(PosCompletedOrder.fromRow).toList();
    } on PostgrestException catch (e) {
      throw PosFailure(_friendly(e.message));
    } catch (_) {
      throw const PosTransientFailure("Couldn't load today's orders.");
    }
  }

  Future<PosOrder?> order(String orderId) async {
    final row = await _client
        .from('orders')
        .select(_orderSelect)
        .eq('id', orderId)
        .eq('tenant_id', _tenantId)
        .maybeSingle();
    return row == null ? null : PosOrder.fromRow(row);
  }

  /// Create an order in one call.
  ///
  /// The idempotency key is **minted here, by the client, and reused across
  /// retries**. `place_staff_order` has a replay fast-path that returns the
  /// existing order before any write, so a resend can't duplicate an order or
  /// orphan a customer. Milestone F's outbox depends on this being caller-owned.
  Future<String> placeOrder({
    required List<CartLine> lines,
    required String orderType,
    String? tableId,
    int? guests,
    String? idempotencyKey,
  }) {
    if (lines.isEmpty) throw const PosFailure('Add something first.');
    return placeOrderJson(
      items: lines.map((l) => l.toRpcJson()).toList(),
      orderType: orderType,
      tableId: tableId,
      guests: guests,
      idempotencyKey: idempotencyKey ?? _uuid.v4(),
    );
  }

  /// The same call, taking the JSON the outbox persisted.
  ///
  /// A queued order must survive a restart, and a [CartLine] holds a live
  /// [PosMenuItem]; only the RPC shape is storable. Both entry points share
  /// this body so a replayed order can't be priced differently from a live one.
  Future<String> placeOrderJson({
    required List<Map<String, dynamic>> items,
    required String orderType,
    String? tableId,
    int? guests,
    required String idempotencyKey,
  }) async {
    try {
      final id = await _client.rpc(
        'place_staff_order',
        params: {
          '_tenant': _tenantId,
          '_idempotency_key': idempotencyKey,
          '_table_id': tableId,
          '_order_type': orderType,
          '_items': items,
          '_guests': ?guests,
        },
      );
      return id as String;
    } on PostgrestException catch (e) {
      throw PosFailure(_friendly(e.message));
    } catch (_) {
      throw const PosTransientFailure(
        "Couldn't reach the server. The order was not placed.",
      );
    }
  }

  /// Add a line to an existing order — the shared RPC, same one the web uses,
  /// so pricing can't drift between the two clients.
  Future<String> addItem({required String orderId, required CartLine line}) =>
      addItemJson(orderId: orderId, item: line.toRpcJson());

  /// The same call, taking the JSON the outbox persisted. Keys match
  /// [CartLine.toRpcJson] exactly, so a queued amend replays as itself.
  Future<String> addItemJson({
    required String orderId,
    required Map<String, dynamic> item,
  }) async {
    // An off-menu line has no `item_id` to look a price up by, so it goes to
    // its own RPC — which clamps the hand-typed price and writes the
    // `custom_price` audit row in the same transaction as the line.
    final customName = item['custom_name'] as String?;
    try {
      final id = customName == null
          ? await _client.rpc(
              'amend_order_add_item',
              params: {
                '_order_id': orderId,
                '_item_id': item['item_id'],
                '_qty': item['qty'],
                '_variant_id': ?item['variant_id'],
                '_modifier_ids': ?item['modifier_ids'],
                '_notes': ?item['notes'],
              },
            )
          : await _client.rpc(
              'amend_order_add_custom_item',
              params: {
                '_order_id': orderId,
                '_name': customName,
                '_unit_price_cents': item['unit_price_cents'],
                '_qty': item['qty'],
                '_notes': ?item['notes'],
              },
            );
      return id as String;
    } on PostgrestException catch (e) {
      throw PosFailure(_friendly(e.message));
    } catch (_) {
      throw const PosTransientFailure(
        "Couldn't reach the server. Nothing was added.",
      );
    }
  }

  /// Delete a line that was never fired. A fired line must be voided instead —
  /// it's on a kitchen ticket, so removing it needs a reason and an audit row.
  Future<void> deleteDraftLine(String lineId) async {
    try {
      await _client
          .from('order_items')
          .delete()
          .eq('id', lineId)
          .eq('tenant_id', _tenantId)
          .eq('status', 'draft');
    } catch (_) {
      throw const PosTransientFailure("Couldn't remove that line.");
    }
  }

  /// Void a fired line. Manager-gated, reason required, audited — all enforced
  /// inside the RPC, so the app must not offer a path that skips it.
  Future<void> voidLine({
    required String lineId,
    required String reason,
  }) async {
    if (reason.trim().isEmpty) {
      throw const PosFailure('A void needs a reason.');
    }
    try {
      await _client.rpc(
        'void_order_item',
        params: {'_order_item_id': lineId, '_reason': reason.trim()},
      );
    } on PostgrestException catch (e) {
      throw PosFailure(_friendly(e.message));
    }
  }

  Future<void> setLineQty({required String lineId, required int qty}) async {
    final clamped = qty.clamp(1, 99);
    try {
      await _client
          .from('order_items')
          .update({'qty': clamped})
          .eq('id', lineId)
          .eq('tenant_id', _tenantId)
          .eq('status', 'draft');
    } catch (_) {
      throw const PosTransientFailure("Couldn't change the quantity.");
    }
  }

  /// Send to the kitchen. Splits per station into KOTs server-side; idempotent,
  /// so a double-tap can't double-print.
  Future<void> fireOrder(String orderId) async {
    try {
      await _client.rpc('fire_order', params: {'_order_id': orderId});
    } on PostgrestException catch (e) {
      throw PosFailure(_friendly(e.message));
    } catch (_) {
      throw const PosTransientFailure(
        "Couldn't reach the kitchen. Check the order before re-firing.",
      );
    }
  }

  /// Accept a guest's QR order and send it to the kitchen.
  ///
  /// Only reachable when the tenant turned off `qr_auto_fire` — with it on (the
  /// default) `place_qr_order` builds the tickets itself and the order arrives
  /// on the board already `in_kitchen`. Returns how many tickets it made; zero
  /// means the lines were already ticketed, which is a no-op, not an error.
  Future<int> acceptQrOrder(String orderId) async {
    try {
      final res = await _client.rpc(
        'accept_qr_order',
        params: {'_order_id': orderId},
      );
      return (res as num?)?.toInt() ?? 0;
    } on PostgrestException catch (e) {
      throw PosFailure(_friendly(e.message));
    } catch (_) {
      throw const PosTransientFailure(
        "Couldn't reach the kitchen. Check the order before sending it again.",
      );
    }
  }

  /// Keep an order at the top of the board, or let it go.
  ///
  /// A direct column write rather than an RPC, and deliberately: `pinned_at`
  /// decides no money, no stock and no access, RLS on `orders` is tenant-scoped,
  /// and the web does exactly the same thing. Anything a *role* should gate
  /// belongs in a `security definer` function — this is a display preference.
  Future<void> setPinned({
    required String orderId,
    required bool pinned,
  }) async {
    try {
      await _client
          .from('orders')
          .update({
            'pinned_at': pinned
                ? DateTime.now().toUtc().toIso8601String()
                : null,
          })
          .eq('id', orderId)
          .eq('tenant_id', _tenantId);
    } on PostgrestException catch (e) {
      // A refusal is final and a timeout is not — conflating them is the
      // classification bug `PLANNING.md` §2 rule 3 exists to prevent.
      throw PosFailure(_friendly(e.message));
    } catch (_) {
      throw const PosTransientFailure("Couldn't pin that order.");
    }
  }

  /// How many people are eating, which is what turns covers into a real average
  /// spend on the reports. Clamped the same way the web action clamps it.
  Future<void> setGuests({required String orderId, required int guests}) async {
    try {
      await _client
          .from('orders')
          .update({'guests': guests.clamp(1, 200)})
          .eq('id', orderId)
          .eq('tenant_id', _tenantId);
    } on PostgrestException catch (e) {
      throw PosFailure(_friendly(e.message));
    } catch (_) {
      throw const PosTransientFailure("Couldn't save the guest count.");
    }
  }

  Future<void> cancelOrder({
    required String orderId,
    required String reason,
  }) async {
    try {
      await _client.rpc(
        'cancel_order',
        params: {'_order_id': orderId, '_reason': reason.trim()},
      );
    } on PostgrestException catch (e) {
      throw PosFailure(_friendly(e.message));
    } catch (_) {
      // A cancel that timed out may or may not have landed, and the two look
      // identical from here. Say so rather than reporting a cancel that didn't
      // happen — the board refreshes and shows the truth.
      throw const PosTransientFailure(
        "Couldn't reach the server. Check the order before cancelling again.",
      );
    }
  }

  // --- Table operations ----------------------------------------------------

  /// The order sitting on a table, for the table-actions sheet.
  ///
  /// **Deliberately not [activeOrders]'s filter.** That one hides `billed`
  /// orders because they belong to the Bills tab; a billed order can still be
  /// transferred, and refusing to find it would strand a table whose guests
  /// moved after asking for the bill. Only `closed` and `cancelled` are history.
  Future<String?> activeOrderIdForTable(String tableId) async {
    try {
      final row = await _client
          .from('orders')
          .select('id')
          .eq('tenant_id', _tenantId)
          .eq('table_id', tableId)
          .not('status', 'in', '("closed","cancelled")')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      return row?['id'] as String?;
    } catch (_) {
      throw const PosTransientFailure("Couldn't check that table's order.");
    }
  }

  /// Move a whole order to another table.
  ///
  /// The RPC frees the old table, occupies the new one and writes the audit
  /// row. Same-table is a no-op server-side, but the sheet refuses it first so
  /// nobody watches a spinner to achieve nothing.
  Future<void> transferOrder({
    required String orderId,
    required String toTableId,
  }) async {
    try {
      await _client.rpc(
        'transfer_order',
        params: {'_order_id': orderId, '_to_table': toTableId},
      );
    } on PostgrestException catch (e) {
      throw PosFailure(_friendly(e.message));
    } catch (_) {
      throw const PosTransientFailure(
        "Couldn't reach the server. Check both tables before trying again.",
      );
    }
  }

  /// Move some lines onto a new order at another table, and return its id.
  ///
  /// The new order is minted server-side, which is why this can never be
  /// queued: there is no id to show until the server answers.
  Future<String> splitOrderItems({
    required String orderId,
    required String toTableId,
    required List<String> itemIds,
  }) async {
    if (itemIds.isEmpty) {
      throw const PosFailure('Pick at least one dish to move.');
    }
    try {
      final id = await _client.rpc<dynamic>(
        'split_order_items',
        params: {
          '_order_id': orderId,
          '_to_table': toTableId,
          '_item_ids': itemIds,
        },
      );
      if (id is! String) {
        throw const PosFailure("Those dishes couldn't be moved.");
      }
      return id;
    } on PostgrestException catch (e) {
      throw PosFailure(_friendly(e.message));
    } on PosFailure {
      rethrow;
    } catch (_) {
      throw const PosTransientFailure(
        "Couldn't reach the server. Check the order before trying again.",
      );
    }
  }

  // --- Manager ops ---------------------------------------------------------

  /// Mark a dish sold out, or put it back.
  ///
  /// Goes through `set_item_86`, not a column update: RLS on `menu_items` is
  /// tenant-scoped only, so a direct update would let any member of the
  /// restaurant 86 a dish. The RPC holds the role rule and writes the audit row.
  Future<void> setItem86({required String itemId, required bool is86}) async {
    try {
      await _client.rpc(
        'set_item_86',
        params: {'_item_id': itemId, '_is_86': is86},
      );
    } on PostgrestException catch (e) {
      throw PosFailure(_friendly(e.message));
    } catch (_) {
      throw const PosTransientFailure(
        "Couldn't reach the server. The menu wasn't changed.",
      );
    }
  }

  /// Set a table's state. The RPC refuses to free a table that still has a
  /// live order, so the board can't hide an order the kitchen is cooking.
  Future<void> setTableState({
    required String tableId,
    required String state,
  }) async {
    try {
      await _client.rpc(
        'set_table_state',
        params: {'_table_id': tableId, '_state': state},
      );
    } on PostgrestException catch (e) {
      throw PosFailure(_friendly(e.message));
    } catch (_) {
      throw const PosTransientFailure(
        "Couldn't reach the server. The table wasn't changed.",
      );
    }
  }

  /// The manager's log: what was voided, discounted, 86'd or re-stated, by whom.
  ///
  /// `audit_logs` RLS already restricts SELECT to owners and managers, so this
  /// cannot leak to a waiter even if the app asked. The actor's name needs a
  /// second query — the FK points at `auth.users`, which PostgREST cannot embed
  /// through to `profiles`.
  Future<List<PosAuditEntry>> auditLog({
    Set<String> actions = const {
      'void',
      'discount',
      'item_86',
      'item_unset_86',
      'table_state',
    },
    int limit = 100,
  }) async {
    final rows = await _client
        .from('audit_logs')
        .select('id, action, created_at, metadata, actor_id')
        .eq('tenant_id', _tenantId)
        .inFilter('action', actions.toList())
        .order('created_at', ascending: false)
        .limit(limit);

    final actorIds = rows
        .map((r) => r['actor_id'] as String?)
        .nonNulls
        .toSet()
        .toList();

    var actors = <String, Map<String, dynamic>>{};
    if (actorIds.isNotEmpty) {
      final profiles = await _client
          .from('profiles')
          .select('id, full_name, username')
          .inFilter('id', actorIds);
      actors = {for (final p in profiles) p['id'] as String: p};
    }

    // A void's audit row carries the reason but not the dish. Look the lines up
    // in one query — "Void —" is a log entry nobody can act on.
    final lineIds = rows
        .where((r) => r['entity_type'] == 'order_item')
        .map((r) => r['entity_id'] as String?)
        .nonNulls
        .toSet()
        .toList();

    var lineNames = <String, String>{};
    if (lineIds.isNotEmpty) {
      final lines = await _client
          .from('order_items')
          .select('id, name_snapshot')
          .eq('tenant_id', _tenantId)
          .inFilter('id', lineIds);
      lineNames = {
        for (final l in lines)
          if (l['name_snapshot'] != null)
            l['id'] as String: l['name_snapshot'] as String,
      };
    }

    return rows.map((r) {
      final meta = r['metadata'];
      final name = lineNames[r['entity_id']];
      return PosAuditEntry.fromRow({
        ...r,
        if (name != null)
          'metadata': {
            ...(meta is Map<String, dynamic> ? meta : const {}),
            'name_snapshot': name,
          },
        'actor': actors[r['actor_id']],
      });
    }).toList();
  }

  /// Turn the RPCs' SQL prose into something a waiter can act on. Anything
  /// unmapped passes through — an opaque message beats a swallowed one.
  static String _friendly(String message) {
    final m = message.toLowerCase();
    if (m.contains('modifier not available')) {
      return "That add-on isn't available for this dish.";
    }
    if (m.contains("is 86'd") || m.contains('out of stock')) {
      return message.split('\n').first;
    }
    if (m.contains('cannot be amended')) {
      return "This order is closed — it can't be changed.";
    }
    if (m.contains('not authorized') || m.contains('not permitted')) {
      return "You don't have permission to do that.";
    }
    if (m.contains('variant not found')) {
      return 'That size is no longer available.';
    }
    if (m.contains('item not found')) {
      return 'That dish is no longer on the menu.';
    }
    if (m.contains('no valid items')) {
      return 'None of those dishes are available any more.';
    }
    if (m.contains('already taken a payment')) {
      return 'This bill has already been paid — start a new order for the table.';
    }
    if (m.contains('table implies')) {
      return 'Pick a table or takeaway, not both.';
    }
    return message;
  }
}

final posRepositoryProvider = Provider.family<PosRepository, String>(
  (ref, tenantId) => PosRepository(ref.watch(supabaseProvider), tenantId),
);
