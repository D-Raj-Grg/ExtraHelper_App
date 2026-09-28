import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'pos_repository.dart' show PosFailure, PosTransientFailure;
import 'supabase_providers.dart';

/// A dish as the menu editor sees it: name, price, category, photo, veg mark,
/// stock and sizes. Add-ons, availability windows and combos stay on the web.
class MenuEditItem {
  const MenuEditItem({
    required this.id,
    required this.name,
    required this.basePriceCents,
    required this.variants,
    this.categoryId,
    this.categoryName,
    this.description,
    this.imageUrl,
    this.isVeg,
    this.stationIds = const [],
    this.addOns = const [],
    this.availability = const [],
    this.is86 = false,
    this.costCents,
  });

  final String id;
  final String name;
  final int basePriceCents;

  /// What it costs to make, for profit reports. Null = never entered, or
  /// null unless the caller holds `profit.view` (RLS hides the
  /// `menu_item_costs` row, so the embed comes back null, not an error).
  final int? costCents;
  final List<MenuEditVariant> variants;
  final String? categoryId;
  final String? categoryName;
  final String? description;
  final String? imageUrl;

  /// Tri-state on purpose: null is "not marked", which is not "non-veg".
  final bool? isVeg;

  /// Every kitchen station its tickets go to. Empty = no station route.
  final List<String> stationIds;

  /// Add-ons from the library linked to this dish.
  final List<MenuAddOnLink> addOns;

  /// When it may be sold. Empty = always.
  final List<MenuAvailability> availability;
  final bool is86;

  static MenuEditItem fromJson(Map<String, dynamic> j) {
    final variants =
        (j['item_variants'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(MenuEditVariant.fromJson)
            .toList()
          // Belt and braces: the query orders by `sort`, but a row written
          // before the column existed can share the value, and the tie-break
          // has to match the till's or the two screens disagree.
          ..sort((a, b) {
            final bySort = a.sort.compareTo(b.sort);
            return bySort != 0
                ? bySort
                : a.priceDeltaCents.compareTo(b.priceDeltaCents);
          });
    return MenuEditItem(
      id: (j['id'] as String?) ?? '',
      name: (j['name'] as String?) ?? '',
      basePriceCents: (j['base_price_cents'] as num?)?.toInt() ?? 0,
      costCents: _embeddedCost(j['menu_item_costs']),
      is86: (j['is_86'] as bool?) ?? false,
      categoryId: j['category_id'] as String?,
      categoryName:
          (j['menu_categories'] as Map<String, dynamic>?)?['name'] as String?,
      description: (j['description'] as String?)?.trim().isEmpty ?? true
          ? null
          : (j['description'] as String).trim(),
      imageUrl: j['image_url'] as String?,
      isVeg: j['is_veg'] as bool?,
      stationIds: [
        for (final r
            in ((j['item_station_routes'] as List<dynamic>?) ?? const [])
                .whereType<Map<String, dynamic>>())
          r['station_id'] as String,
      ],
      addOns: [
        for (final r
            in ((j['item_modifiers'] as List<dynamic>?) ?? const [])
                .whereType<Map<String, dynamic>>())
          MenuAddOnLink(
            modifierId: r['modifier_id'] as String,
            isDefault: r['is_default'] == true,
            maxQty: (r['max_qty'] as num?)?.toInt() ?? 1,
          ),
      ],
      availability:
          [
            for (final r
                in ((j['item_availability'] as List<dynamic>?) ?? const [])
                    .whereType<Map<String, dynamic>>())
              MenuAvailability.fromJson(r),
          ]..sort((a, b) {
            final d = (a.dayOfWeek ?? -1).compareTo(b.dayOfWeek ?? -1);
            return d != 0 ? d : a.start.compareTo(b.start);
          }),
      variants: variants,
    );
  }
}

/// One size of a dish. The delta may be negative — a Half is a real variant.
class MenuEditVariant {
  const MenuEditVariant({
    required this.id,
    required this.name,
    required this.priceDeltaCents,
    required this.sort,
    this.costCents,
  });

  final String id;
  final String name;
  final int priceDeltaCents;
  final int sort;

  /// Per-size cost, when it differs from the dish's. Null = falls back, or
  /// null unless the caller holds `profit.view` (RLS hides the
  /// `item_variant_costs` row).
  final int? costCents;

  static MenuEditVariant fromJson(Map<String, dynamic> j) => MenuEditVariant(
    id: (j['id'] as String?) ?? '',
    name: (j['name'] as String?) ?? '',
    priceDeltaCents: (j['price_delta_cents'] as num?)?.toInt() ?? 0,
    sort: (j['sort'] as num?)?.toInt() ?? 0,
    costCents: _embeddedCost(j['item_variant_costs']),
  );
}

/// A one-to-one cost embed (`menu_item_costs(cost_cents)` /
/// `item_variant_costs(cost_cents)`) is `{cost_cents: n}`, or null when RLS
/// hid the row or none was ever written. Absent, null and malformed all read
/// as "unknown", never 0.
int? _embeddedCost(Object? embed) {
  if (embed is! Map) return null;
  return (embed['cost_cents'] as num?)?.toInt();
}

/// Menu editing from the phone.
///
/// **Every write is an RPC, never a table write.** `item_variants` is gated on
/// `menu.edit` at the policy level (`20260814170000`), and the definer function
/// is what carries that permission — the same four calls the web editor makes,
/// so the rules exist once instead of drifting between the two clients.
///
/// Reads go through PostgREST under RLS **plus an explicit tenant filter**, as
/// defense in depth.
class MenuRepository {
  const MenuRepository(this._client, this._tenantId);

  final SupabaseClient _client;
  final String _tenantId;

  static const _columns =
      'id, name, base_price_cents, is_86, category_id, '
      'description, image_url, is_veg, menu_categories(name), '
      'menu_item_costs(cost_cents), '
      'item_station_routes(station_id), '
      'item_modifiers(modifier_id, is_default, max_qty), '
      'item_availability(id, day_of_week, start_time, end_time), '
      'item_variants(id, name, price_delta_cents, sort, '
      'item_variant_costs(cost_cents))';

  /// Every dish, with its sizes in the owner's order.
  ///
  /// Network-only, unlike the till: editing a menu you cannot save is worse
  /// than being told the menu could not be loaded.
  Future<List<MenuEditItem>> items() async {
    try {
      final rows = await _client
          .from('menu_items')
          .select(_columns)
          .eq('tenant_id', _tenantId)
          .order('name')
          .order('sort', referencedTable: 'item_variants');
      return rows.map(MenuEditItem.fromJson).toList();
    } catch (_) {
      throw const PosTransientFailure("Couldn't load the menu.");
    }
  }

  Future<String> addVariant({
    required String itemId,
    required String name,
    required int priceDeltaCents,
  }) async {
    try {
      final id = await _client.rpc<dynamic>(
        'add_variant',
        params: {
          '_item_id': itemId,
          '_name': name,
          '_price_delta_cents': priceDeltaCents,
        },
      );
      return (id as String?) ?? '';
    } on PostgrestException catch (e) {
      throw PosFailure(_friendly(e.message));
    } catch (_) {
      throw const PosTransientFailure(
        "Couldn't add that size. Nothing was changed.",
      );
    }
  }

  Future<void> updateVariant({
    required String variantId,
    required String name,
    required int priceDeltaCents,
  }) async {
    try {
      await _client.rpc<dynamic>(
        'update_variant',
        params: {
          '_variant_id': variantId,
          '_name': name,
          '_price_delta_cents': priceDeltaCents,
        },
      );
    } on PostgrestException catch (e) {
      throw PosFailure(_friendly(e.message));
    } catch (_) {
      throw const PosTransientFailure(
        "Couldn't save that size. Nothing was changed.",
      );
    }
  }

  /// Move a size one place up or down. Returns its new 1-based position; at the
  /// edge the server returns the position it already had rather than erroring.
  Future<int> moveVariant({required String variantId, required bool up}) async {
    try {
      final pos = await _client.rpc<dynamic>(
        'move_variant',
        params: {'_variant_id': variantId, '_direction': up ? 'up' : 'down'},
      );
      return (pos as num?)?.toInt() ?? 0;
    } on PostgrestException catch (e) {
      throw PosFailure(_friendly(e.message));
    } catch (_) {
      throw const PosTransientFailure(
        "Couldn't reorder the sizes. Nothing was changed.",
      );
    }
  }

  Future<void> deleteVariant(String variantId) async {
    try {
      await _client.rpc<dynamic>(
        'delete_variant',
        params: {'_variant_id': variantId},
      );
    } on PostgrestException catch (e) {
      throw PosFailure(_friendly(e.message));
    } catch (_) {
      throw const PosTransientFailure(
        "Couldn't remove that size. Nothing was changed.",
      );
    }
  }
}

/// A menu category, with whether it shows on ordering screens.
class MenuEditCategory {
  const MenuEditCategory({
    required this.id,
    required this.name,
    required this.sort,
    this.isActive = true,
  });

  final String id;
  final String name;
  final int sort;
  final bool isActive;

  static MenuEditCategory fromJson(Map<String, dynamic> j) => MenuEditCategory(
    id: j['id'] as String,
    name: (j['name'] as String?) ?? '',
    sort: (j['sort'] as num?)?.toInt() ?? 0,
    isActive: j['is_active'] != false,
  );
}

/// A dish's link to an add-on in the library.
class MenuAddOnLink {
  const MenuAddOnLink({
    required this.modifierId,
    this.isDefault = false,
    this.maxQty = 1,
  });

  final String modifierId;
  final bool isDefault;
  final int maxQty;
}

/// An add-on in the tenant's library ("Extra cheese", +Rs 50).
class MenuAddOn {
  const MenuAddOn({
    required this.id,
    required this.name,
    required this.priceCents,
  });

  final String id;
  final String name;
  final int priceCents;
}

const dayNames = [
  'Sunday',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
];

/// A window a dish may be sold in. Null day = every day. Times are the
/// restaurant's local wall clock, "HH:MM:SS" as Postgres `time` stores them.
class MenuAvailability {
  const MenuAvailability({
    required this.id,
    required this.dayOfWeek,
    required this.start,
    required this.end,
  });

  final String id;
  final int? dayOfWeek;
  final String start;
  final String end;

  String get dayLabel =>
      dayOfWeek == null ? 'Every day' : dayNames[dayOfWeek!.clamp(0, 6)];

  static String _hm(String t) => t.length >= 5 ? t.substring(0, 5) : t;

  String get window => '${_hm(start)}–${_hm(end)}';

  static MenuAvailability fromJson(Map<String, dynamic> j) => MenuAvailability(
    id: j['id'] as String,
    dayOfWeek: (j['day_of_week'] as num?)?.toInt(),
    start: (j['start_time'] as String?) ?? '00:00:00',
    end: (j['end_time'] as String?) ?? '23:59:00',
  );
}

/// Several dishes at one price. `items` is `[{item_id, qty}]` in a jsonb
/// column, the web's shape.
class MenuCombo {
  const MenuCombo({
    required this.id,
    required this.name,
    required this.priceCents,
    required this.items,
    this.isActive = true,
  });

  final String id;
  final String name;
  final int priceCents;
  final List<({String itemId, int qty})> items;
  final bool isActive;

  static MenuCombo fromJson(Map<String, dynamic> j) => MenuCombo(
    id: j['id'] as String,
    name: (j['name'] as String?) ?? '',
    priceCents: (j['price_cents'] as num?)?.toInt() ?? 0,
    isActive: j['is_active'] != false,
    items: [
      for (final r
          in ((j['items'] as List<dynamic>?) ?? const [])
              .whereType<Map<String, dynamic>>())
        if (r['item_id'] is String)
          (
            itemId: r['item_id'] as String,
            qty: (r['qty'] as num?)?.toInt() ?? 1,
          ),
    ],
  );
}

class MenuStation {
  const MenuStation({required this.id, required this.name});

  final String id;
  final String name;
}

/// What the item form hands back.
class MenuItemDraft {
  const MenuItemDraft({
    required this.name,
    required this.basePriceCents,
    this.categoryId,
    this.description,
    this.isVeg,
    this.stationIds = const {},
    this.costCents,
    this.costSet = false,
  });

  final String name;
  final int basePriceCents;
  final String? categoryId;
  final String? description;
  final bool? isVeg;
  final Set<String> stationIds;

  /// Cost price. Only written when [costSet]; null then clears it.
  final int? costCents;

  /// False = the field was hidden or untouched, so the stored cost is left
  /// alone. True = write [costCents], null clearing it. Separate from the
  /// value because "no cost" and "didn't ask" must not collapse into one.
  final bool costSet;
}

/// What [MenuItemWrites.createItem] hands back: the new dish's id, plus a
/// warning when the dish was written but its cost was not. The dish is on the
/// menu either way — a failed cost must not read as a failed save.
typedef CreatedMenuItem = ({String id, String? costWarning});

/// Dishes, categories and photos.
///
/// Plain table writes, the same ones the web editor makes: `menu_items`,
/// `menu_categories` and `item_station_routes` are gated on `menu.edit` at the
/// policy level. RLS fails **silently** on a refused write, so every write reads
/// its row back and treats zero rows as a refusal.
extension MenuItemWrites on MenuRepository {
  static const _refused = PosFailure(
    "You don't have permission to edit the menu. An owner or manager can "
    'grant it under Team.',
  );

  Future<List<MenuEditCategory>> categories() async {
    try {
      final rows = await _client
          .from('menu_categories')
          .select('id, name, sort, is_active')
          .eq('tenant_id', _tenantId)
          .order('sort')
          .order('name');
      return rows.map(MenuEditCategory.fromJson).toList();
    } catch (_) {
      throw const PosTransientFailure("Couldn't load the categories.");
    }
  }

  Future<List<MenuStation>> stations() async {
    try {
      final rows = await _client
          .from('kitchen_stations')
          .select('id, name')
          .eq('tenant_id', _tenantId)
          .order('name');
      return [
        for (final r in rows)
          MenuStation(
            id: r['id'] as String,
            name: (r['name'] as String?) ?? '',
          ),
      ];
    } catch (_) {
      throw const PosTransientFailure("Couldn't load the kitchen stations.");
    }
  }

  Future<String> createCategory(String name) => _write(() async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw const PosFailure('Give the category a name.');
    final rows = await _client
        .from('menu_categories')
        .insert({'tenant_id': _tenantId, 'name': trimmed})
        .select('id');
    if (rows.isEmpty) throw _refused;
    return rows.first['id'] as String;
  }, "Couldn't add that category just now.");

  Future<void> updateCategory(String id, {String? name, bool? isActive}) =>
      _write(() async {
        final patch = <String, dynamic>{
          if (name != null) 'name': name.trim(),
          'is_active': ?isActive,
        };
        if (patch['name'] == '') {
          throw const PosFailure('Give the category a name.');
        }
        if (patch.isEmpty) return;
        final rows = await _client
            .from('menu_categories')
            .update(patch)
            .eq('id', id)
            .eq('tenant_id', _tenantId)
            .select('id');
        if (rows.isEmpty) throw _refused;
      }, "Couldn't save that category just now.");

  /// Inserts the dish, then its stations and cost. The cost is validated
  /// **before** the insert so a bad value never leaves a half-made dish; a cost
  /// RPC that fails *after* the row exists comes back as [CreatedMenuItem]
  /// `costWarning` rather than a thrown failure, because throwing would tell
  /// the person the dish was not added when it was.
  Future<CreatedMenuItem> createItem(MenuItemDraft d) => _write(() async {
    if (d.costSet) _checkCost(d.costCents);
    final rows = await _client
        .from('menu_items')
        .insert({
          'tenant_id': _tenantId,
          'name': d.name.trim(),
          'base_price_cents': d.basePriceCents,
          'category_id': d.categoryId,
          'description': _blankToNull(d.description),
          'is_veg': d.isVeg,
        })
        .select('id');
    if (rows.isEmpty) throw _refused;
    final id = rows.first['id'] as String;
    await _setStations(id, d.stationIds);
    String? costWarning;
    if (d.costSet) {
      try {
        await setItemCost(id, d.costCents);
      } on PosFailure catch (e) {
        costWarning = 'Dish saved, but the cost was not. ${e.message}';
      }
    }
    return (id: id, costWarning: costWarning);
  }, "Couldn't add that dish just now.");

  Future<void> updateItem(String id, MenuItemDraft d) => _write(() async {
    if (d.costSet) _checkCost(d.costCents);
    final rows = await _client
        .from('menu_items')
        .update({
          'name': d.name.trim(),
          'base_price_cents': d.basePriceCents,
          'category_id': d.categoryId,
          'description': _blankToNull(d.description),
          'is_veg': d.isVeg,
        })
        .eq('id', id)
        .eq('tenant_id', _tenantId)
        .select('id');
    if (rows.isEmpty) throw _refused;
    await _setStations(id, d.stationIds);
    if (d.costSet) await setItemCost(id, d.costCents);
  }, "Couldn't save that dish just now.");

  /// Cost price, through the `set_item_cost` RPC: it carries the `profit.view`
  /// check (42501 without it), unlike the table columns. Null clears.
  Future<void> setItemCost(String id, int? cents) => _write(
    () => _client.rpc<dynamic>(
      'set_item_cost',
      params: {'_item_id': id, '_cost_cents': cents},
    ),
    "Couldn't save the cost just now.",
  );

  /// Deleting keeps order history: order lines snapshot the name and price.
  Future<void> deleteItem(String id) => _write(() async {
    final rows = await _client
        .from('menu_items')
        .delete()
        .eq('id', id)
        .eq('tenant_id', _tenantId)
        .select('id');
    if (rows.isEmpty) throw _refused;
  }, "Couldn't delete that dish just now.");

  /// Make the dish's station routes exactly [wanted]: add the missing ones,
  /// remove the rest, and leave matching routes alone.
  Future<void> _setStations(String itemId, Set<String> wanted) async {
    final current = await _client
        .from('item_station_routes')
        .select('station_id')
        .eq('tenant_id', _tenantId)
        .eq('item_id', itemId);
    final have = current.map((r) => r['station_id'] as String).toSet();
    final drop = have.difference(wanted);
    final add = wanted.difference(have);
    if (drop.isNotEmpty) {
      await _client
          .from('item_station_routes')
          .delete()
          .eq('tenant_id', _tenantId)
          .eq('item_id', itemId)
          .inFilter('station_id', drop.toList());
    }
    if (add.isNotEmpty) {
      await _client.from('item_station_routes').insert([
        for (final sid in add)
          {'tenant_id': _tenantId, 'item_id': itemId, 'station_id': sid},
      ]);
    }
  }

  // --- Add-ons ------------------------------------------------------------

  Future<List<MenuAddOn>> addOns() async {
    try {
      final rows = await _client
          .from('modifiers')
          .select('id, name, price_cents')
          .eq('tenant_id', _tenantId)
          .order('name');
      return [
        for (final r in rows)
          MenuAddOn(
            id: r['id'] as String,
            name: (r['name'] as String?) ?? '',
            priceCents: (r['price_cents'] as num?)?.toInt() ?? 0,
          ),
      ];
    } catch (_) {
      throw const PosTransientFailure("Couldn't load the add-ons.");
    }
  }

  Future<String> createAddOn(String name, int priceCents) => _write(() async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw const PosFailure('Give the add-on a name.');
    final rows = await _client
        .from('modifiers')
        .insert({
          'tenant_id': _tenantId,
          'name': trimmed,
          'price_cents': priceCents,
        })
        .select('id');
    if (rows.isEmpty) throw _refused;
    return rows.first['id'] as String;
  }, "Couldn't add that add-on just now.");

  Future<void> updateAddOn(String id, String name, int priceCents) =>
      _write(() async {
        final trimmed = name.trim();
        if (trimmed.isEmpty) throw const PosFailure('Give the add-on a name.');
        final rows = await _client
            .from('modifiers')
            .update({'name': trimmed, 'price_cents': priceCents})
            .eq('id', id)
            .eq('tenant_id', _tenantId)
            .select('id');
        if (rows.isEmpty) throw _refused;
      }, "Couldn't save that add-on just now.");

  /// Removes it from every dish it was linked to. Past orders keep their line.
  Future<void> deleteAddOn(String id) => _write(() async {
    final rows = await _client
        .from('modifiers')
        .delete()
        .eq('id', id)
        .eq('tenant_id', _tenantId)
        .select('id');
    if (rows.isEmpty) throw _refused;
  }, "Couldn't delete that add-on just now.");

  /// Link or re-link (upsert on `item_id, modifier_id`, as the web does).
  Future<void> linkAddOn({
    required String itemId,
    required String modifierId,
    bool isDefault = false,
    int maxQty = 1,
  }) => _write(() async {
    final rows = await _client
        .from('item_modifiers')
        .upsert({
          'tenant_id': _tenantId,
          'item_id': itemId,
          'modifier_id': modifierId,
          'is_default': isDefault,
          'max_qty': maxQty < 1 ? 1 : maxQty,
        }, onConflict: 'item_id,modifier_id')
        .select('id');
    if (rows.isEmpty) throw _refused;
  }, "Couldn't link that add-on just now.");

  Future<void> unlinkAddOn({
    required String itemId,
    required String modifierId,
  }) => _write(() async {
    final rows = await _client
        .from('item_modifiers')
        .delete()
        .eq('tenant_id', _tenantId)
        .eq('item_id', itemId)
        .eq('modifier_id', modifierId)
        .select('id');
    if (rows.isEmpty) throw _refused;
  }, "Couldn't remove that add-on just now.");

  // --- Availability -------------------------------------------------------

  /// [start]/[end] are "HH:MM" in the restaurant's local time.
  Future<void> addAvailability({
    required String itemId,
    required int? dayOfWeek,
    required String start,
    required String end,
  }) => _write(() async {
    if (start == end) {
      throw const PosFailure('The window needs a start and a later end.');
    }
    final rows = await _client
        .from('item_availability')
        .insert({
          'tenant_id': _tenantId,
          'item_id': itemId,
          'day_of_week': dayOfWeek,
          'start_time': start,
          'end_time': end,
        })
        .select('id');
    if (rows.isEmpty) throw _refused;
  }, "Couldn't add that time window just now.");

  Future<void> removeAvailability(String id) => _write(() async {
    final rows = await _client
        .from('item_availability')
        .delete()
        .eq('id', id)
        .eq('tenant_id', _tenantId)
        .select('id');
    if (rows.isEmpty) throw _refused;
  }, "Couldn't remove that time window just now.");

  // --- Combos -------------------------------------------------------------

  Future<List<MenuCombo>> combos() async {
    try {
      final rows = await _client
          .from('combos')
          .select('id, name, price_cents, items, is_active')
          .eq('tenant_id', _tenantId)
          .order('name');
      return rows.map(MenuCombo.fromJson).toList();
    } catch (_) {
      throw const PosTransientFailure("Couldn't load the combos.");
    }
  }

  Future<void> saveCombo({
    String? id,
    required String name,
    required int priceCents,
    required List<({String itemId, int qty})> items,
  }) => _write(() async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw const PosFailure('Give the combo a name.');
    if (items.isEmpty) {
      throw const PosFailure('Add at least one dish to the combo.');
    }
    final body = {
      'name': trimmed,
      'price_cents': priceCents,
      'items': [
        for (final i in items) {'item_id': i.itemId, 'qty': i.qty},
      ],
    };
    final rows = id == null
        ? await _client
              .from('combos')
              .insert({'tenant_id': _tenantId, ...body})
              .select('id')
        : await _client
              .from('combos')
              .update(body)
              .eq('id', id)
              .eq('tenant_id', _tenantId)
              .select('id');
    if (rows.isEmpty) throw _refused;
  }, "Couldn't save that combo just now.");

  Future<void> setComboActive(String id, bool active) => _write(() async {
    final rows = await _client
        .from('combos')
        .update({'is_active': active})
        .eq('id', id)
        .eq('tenant_id', _tenantId)
        .select('id');
    if (rows.isEmpty) throw _refused;
  }, "Couldn't change that combo just now.");

  Future<void> deleteCombo(String id) => _write(() async {
    final rows = await _client
        .from('combos')
        .delete()
        .eq('id', id)
        .eq('tenant_id', _tenantId)
        .select('id');
    if (rows.isEmpty) throw _refused;
  }, "Couldn't delete that combo just now.");

  /// Same path shape as the web (`{tenant}/{item}.{ext}`, upserted), so the
  /// two clients replace each other's photo rather than piling up copies.
  Future<void> uploadItemPhoto({
    required String itemId,
    required Uint8List bytes,
    required String ext,
    required String contentType,
  }) => _write(() async {
    final clean = ext.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
    final path = '$_tenantId/$itemId.${clean.isEmpty ? 'jpg' : clean}';
    await _client.storage
        .from('menu-images')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(upsert: true, contentType: contentType),
        );
    final url = _client.storage.from('menu-images').getPublicUrl(path);
    // Cache-bust: the path is stable, so every screen would keep the old one.
    final rows = await _client
        .from('menu_items')
        .update({
          'image_url': '$url?v=${DateTime.now().millisecondsSinceEpoch}',
        })
        .eq('id', itemId)
        .eq('tenant_id', _tenantId)
        .select('id');
    if (rows.isEmpty) throw _refused;
  }, "Couldn't upload that photo just now.");

  Future<void> removeItemPhoto(String itemId) => _write(() async {
    final rows = await _client
        .from('menu_items')
        .update({'image_url': null})
        .eq('id', itemId)
        .eq('tenant_id', _tenantId)
        .select('id');
    if (rows.isEmpty) throw _refused;
  }, "Couldn't remove that photo just now.");

  /// Same bounds as `set_item_cost` on the server, checked here first so the
  /// person is told before anything is written.
  static const maxCostCents = 100000000;

  static void _checkCost(int? cents) {
    if (cents == null) return;
    if (cents < 0 || cents > maxCostCents) {
      throw const PosFailure(
        'Enter a cost price between 0 and 1,000,000, or leave it blank.',
      );
    }
  }

  static String? _blankToNull(String? v) {
    final t = v?.trim() ?? '';
    return t.isEmpty ? null : t;
  }

  Future<T> _write<T>(Future<T> Function() work, String offline) async {
    try {
      return await work();
    } on PostgrestException catch (e) {
      throw PosFailure(_friendly(e.message));
    } on StorageException catch (e) {
      throw PosFailure(e.message);
    } on PosFailure {
      rethrow;
    } catch (_) {
      throw PosTransientFailure(offline);
    }
  }
}

/// Server prose → something the person holding the phone can act on.
String _friendly(String raw) {
  final m = raw.toLowerCase();
  if (m.contains('require') && m.contains('manager')) {
    return "Your role can't change the menu. An owner or manager can grant "
        'that under Team.';
  }
  if (m.contains('permission denied')) {
    return "You don't have permission to edit the menu.";
  }
  if (m.contains('name is required')) {
    return 'Give the size a name — Small, Half, 1 kg.';
  }
  if (m.contains('not found')) {
    return 'That size is already gone. Pull to refresh.';
  }
  return raw;
}

final menuRepositoryProvider = Provider.family<MenuRepository, String>(
  (ref, tenantId) => MenuRepository(ref.watch(supabaseProvider), tenantId),
);
