import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'pos_repository.dart' show PosFailure, PosTransientFailure;
import 'supabase_providers.dart';

/// A dish as the menu editor sees it — enough to find it and to price its
/// sizes, not the whole record the web editor holds (photo, add-ons, routing,
/// availability all stay web-only for now).
class MenuEditItem {
  const MenuEditItem({
    required this.id,
    required this.name,
    required this.basePriceCents,
    required this.variants,
    this.categoryName,
    this.is86 = false,
  });

  final String id;
  final String name;
  final int basePriceCents;
  final List<MenuEditVariant> variants;
  final String? categoryName;
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
      is86: (j['is_86'] as bool?) ?? false,
      categoryName:
          (j['menu_categories'] as Map<String, dynamic>?)?['name'] as String?,
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
  });

  final String id;
  final String name;
  final int priceDeltaCents;
  final int sort;

  static MenuEditVariant fromJson(Map<String, dynamic> j) => MenuEditVariant(
    id: (j['id'] as String?) ?? '',
    name: (j['name'] as String?) ?? '',
    priceDeltaCents: (j['price_delta_cents'] as num?)?.toInt() ?? 0,
    sort: (j['sort'] as num?)?.toInt() ?? 0,
  );
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
      'id, name, base_price_cents, is_86, '
      'menu_categories(name), '
      'item_variants(id, name, price_delta_cents, sort)';

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

/// Server prose → something the person holding the phone can act on.
String _friendly(String raw) {
  final m = raw.toLowerCase();
  if (m.contains('require') && m.contains('manager')) {
    return "Your role can't change the menu. An owner or manager can grant "
        'that under Team on the web app.';
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
