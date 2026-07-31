import 'package:drift/drift.dart';

import '../../features/pos/models.dart';
import '../supabase/inventory_repository.dart' show InventoryItem;
import 'database.dart';

/// The read path, on disk.
///
/// Every screen must render correctly **from cache alone** (`CLAUDE.md` rule 5)
/// — the network and Realtime are freshness, not truth.
///
/// The cache is tenant-stamped and [adoptTenant] wipes every other tenant's
/// rows on switch, so one restaurant's menu can never render under another's
/// name. That is rule 2, applied to local storage.
class PosCache {
  PosCache(this._db);

  final AppDatabase _db;

  /// Make [tenantId] the only tenant in the cache. Called on sign-in and on
  /// every tenant switch, before anything is read.
  /// Drops every row that belongs to a *different* tenant, and keeps this
  /// tenant's own.
  ///
  /// Deliberately not "wipe unless the stamp matches": on the very first run
  /// `cache_meta` is empty, and the shell has already cached this tenant's
  /// permissions by the time the POS mounts. A blanket wipe deleted them, and
  /// the next cold start with no coverage rendered "No ordering access". Keying
  /// the delete on `tenant_id` is immune to who wrote first.
  Future<void> adoptTenant(String tenantId) => _db.transaction(() async {
    await (_db.delete(
      _db.cachedCategories,
    )..where((t) => t.tenantId.equals(tenantId).not())).go();
    await (_db.delete(
      _db.cachedMenuItems,
    )..where((t) => t.tenantId.equals(tenantId).not())).go();
    await (_db.delete(
      _db.cachedVariants,
    )..where((t) => t.tenantId.equals(tenantId).not())).go();
    await (_db.delete(
      _db.cachedModifiers,
    )..where((t) => t.tenantId.equals(tenantId).not())).go();
    await (_db.delete(
      _db.cachedItemModifiers,
    )..where((t) => t.tenantId.equals(tenantId).not())).go();
    await (_db.delete(
      _db.cachedFloors,
    )..where((t) => t.tenantId.equals(tenantId).not())).go();
    await (_db.delete(
      _db.cachedTables,
    )..where((t) => t.tenantId.equals(tenantId).not())).go();
    await (_db.delete(
      _db.cachedPermissions,
    )..where((t) => t.tenantId.equals(tenantId).not())).go();
    await (_db.delete(
      _db.cachedInventoryItems,
    )..where((t) => t.tenantId.equals(tenantId).not())).go();
    await (_db.delete(
      _db.cacheMeta,
    )..where((t) => t.tenantId.equals(tenantId).not())).go();
  });

  Future<void> wipe() => _db.transaction(() async {
    await _db.delete(_db.cachedCategories).go();
    await _db.delete(_db.cachedMenuItems).go();
    await _db.delete(_db.cachedVariants).go();
    await _db.delete(_db.cachedModifiers).go();
    await _db.delete(_db.cachedItemModifiers).go();
    await _db.delete(_db.cachedFloors).go();
    await _db.delete(_db.cachedTables).go();
    await _db.delete(_db.cachedPermissions).go();
    await _db.delete(_db.cachedInventoryItems).go();
    await _db.delete(_db.cacheMeta).go();
  });

  /// The store room, cached for a count with no coverage.
  Future<void> saveInventory(String tenantId, List<InventoryItem> rows) =>
      _db.transaction(() async {
        await (_db.delete(
          _db.cachedInventoryItems,
        )..where((t) => t.tenantId.equals(tenantId))).go();
        await _db.batch((b) {
          for (final i in rows) {
            b.insert(
              _db.cachedInventoryItems,
              CachedInventoryItemsCompanion.insert(
                tenantId: tenantId,
                id: i.id,
                name: i.name,
                uom: i.uom,
                currentQty: i.currentQty,
                reorderLevel: i.reorderLevel,
                costCents: i.costCents,
                category: Value(i.category),
                barcode: Value(i.barcode),
              ),
              mode: InsertMode.insertOrReplace,
            );
          }
        });
      });

  Future<List<InventoryItem>> inventory(String tenantId) async {
    final rows =
        await (_db.select(_db.cachedInventoryItems)
              ..where((t) => t.tenantId.equals(tenantId))
              ..orderBy([(t) => OrderingTerm.asc(t.name)]))
            .get();
    return rows
        .map(
          (r) => InventoryItem(
            id: r.id,
            name: r.name,
            uom: r.uom,
            currentQty: r.currentQty,
            reorderLevel: r.reorderLevel,
            costCents: r.costCents,
            category: r.category,
            barcode: r.barcode,
          ),
        )
        .toList();
  }

  Future<DateTime?> fetchedAt(String tenantId) async {
    final row = await (_db.select(
      _db.cacheMeta,
    )..where((t) => t.tenantId.equals(tenantId))).getSingleOrNull();
    return row?.fetchedAt;
  }

  Future<void> _stamp(String tenantId) => _db
      .into(_db.cacheMeta)
      .insertOnConflictUpdate(
        CacheMetaData(tenantId: tenantId, fetchedAt: DateTime.now()),
      );

  // --- Menu ----------------------------------------------------------------

  Future<void> saveMenu(String tenantId, List<PosMenuItem> items) =>
      _db.transaction(() async {
        await (_db.delete(
          _db.cachedMenuItems,
        )..where((t) => t.tenantId.equals(tenantId))).go();
        await (_db.delete(
          _db.cachedVariants,
        )..where((t) => t.tenantId.equals(tenantId))).go();
        await (_db.delete(
          _db.cachedModifiers,
        )..where((t) => t.tenantId.equals(tenantId))).go();
        await (_db.delete(
          _db.cachedItemModifiers,
        )..where((t) => t.tenantId.equals(tenantId))).go();

        await _db.batch((b) {
          for (final item in items) {
            b.insert(
              _db.cachedMenuItems,
              CachedMenuItemsCompanion.insert(
                tenantId: tenantId,
                id: item.id,
                name: item.name,
                basePriceCents: item.basePriceCents,
                categoryId: Value(item.categoryId),
                is86: item.is86,
                isVeg: Value(item.isVeg),
                imageUrl: Value(item.imageUrl),
              ),
              mode: InsertMode.insertOrReplace,
            );
            for (final v in item.variants) {
              b.insert(
                _db.cachedVariants,
                CachedVariantsCompanion.insert(
                  tenantId: tenantId,
                  id: v.id,
                  itemId: item.id,
                  name: v.name,
                  priceDeltaCents: v.priceDeltaCents,
                ),
                mode: InsertMode.insertOrReplace,
              );
            }
            for (final m in item.modifiers) {
              b.insert(
                _db.cachedModifiers,
                CachedModifiersCompanion.insert(
                  tenantId: tenantId,
                  id: m.id,
                  name: m.name,
                  priceCents: m.priceCents,
                ),
                mode: InsertMode.insertOrReplace,
              );
              b.insert(
                _db.cachedItemModifiers,
                CachedItemModifiersCompanion.insert(
                  tenantId: tenantId,
                  itemId: item.id,
                  modifierId: m.id,
                ),
                mode: InsertMode.insertOrReplace,
              );
            }
          }
        });
        await _stamp(tenantId);
      });

  Future<List<PosMenuItem>> menu(String tenantId) async {
    final items =
        await (_db.select(_db.cachedMenuItems)
              ..where((t) => t.tenantId.equals(tenantId))
              ..orderBy([(t) => OrderingTerm.asc(t.name)]))
            .get();
    if (items.isEmpty) return const [];

    final variants = await (_db.select(
      _db.cachedVariants,
    )..where((t) => t.tenantId.equals(tenantId))).get();
    final modifiers = await (_db.select(
      _db.cachedModifiers,
    )..where((t) => t.tenantId.equals(tenantId))).get();
    final links = await (_db.select(
      _db.cachedItemModifiers,
    )..where((t) => t.tenantId.equals(tenantId))).get();

    final modifierById = {for (final m in modifiers) m.id: m};
    final variantsByItem = <String, List<CachedVariant>>{};
    for (final v in variants) {
      variantsByItem.putIfAbsent(v.itemId, () => []).add(v);
    }
    final modifierIdsByItem = <String, List<String>>{};
    for (final l in links) {
      modifierIdsByItem.putIfAbsent(l.itemId, () => []).add(l.modifierId);
    }

    return items.map((r) {
      final vs =
          (variantsByItem[r.id] ?? const <CachedVariant>[])
              .map(
                (v) => PosVariant(
                  id: v.id,
                  name: v.name,
                  priceDeltaCents: v.priceDeltaCents,
                ),
              )
              .toList()
            ..sort((a, b) => a.priceDeltaCents.compareTo(b.priceDeltaCents));

      final ms = (modifierIdsByItem[r.id] ?? const <String>[])
          .map((id) => modifierById[id])
          .nonNulls
          .map(
            (m) =>
                PosModifier(id: m.id, name: m.name, priceCents: m.priceCents),
          )
          .toList();

      return PosMenuItem(
        id: r.id,
        name: r.name,
        basePriceCents: r.basePriceCents,
        categoryId: r.categoryId,
        is86: r.is86,
        imageUrl: r.imageUrl,
        isVeg: r.isVeg,
        variants: vs,
        modifiers: ms,
      );
    }).toList();
  }

  // --- Categories ----------------------------------------------------------

  Future<void> saveCategories(String tenantId, List<PosCategory> rows) =>
      _db.transaction(() async {
        await (_db.delete(
          _db.cachedCategories,
        )..where((t) => t.tenantId.equals(tenantId))).go();
        await _db.batch((b) {
          for (final c in rows) {
            b.insert(
              _db.cachedCategories,
              CachedCategoriesCompanion.insert(
                tenantId: tenantId,
                id: c.id,
                name: c.name,
                sort: c.sort,
              ),
              mode: InsertMode.insertOrReplace,
            );
          }
        });
        await _stamp(tenantId);
      });

  Future<List<PosCategory>> categories(String tenantId) async {
    final rows =
        await (_db.select(_db.cachedCategories)
              ..where((t) => t.tenantId.equals(tenantId))
              ..orderBy([(t) => OrderingTerm.asc(t.sort)]))
            .get();
    return rows
        .map((r) => PosCategory(id: r.id, name: r.name, sort: r.sort))
        .toList();
  }

  // --- Floor ---------------------------------------------------------------

  Future<void> saveFloors(String tenantId, List<PosFloor> rows) =>
      _db.transaction(() async {
        await (_db.delete(
          _db.cachedFloors,
        )..where((t) => t.tenantId.equals(tenantId))).go();
        await _db.batch((b) {
          for (final f in rows) {
            b.insert(
              _db.cachedFloors,
              CachedFloorsCompanion.insert(
                tenantId: tenantId,
                id: f.id,
                name: f.name,
                sort: f.sort,
              ),
              mode: InsertMode.insertOrReplace,
            );
          }
        });
        await _stamp(tenantId);
      });

  Future<List<PosFloor>> floors(String tenantId) async {
    final rows =
        await (_db.select(_db.cachedFloors)
              ..where((t) => t.tenantId.equals(tenantId))
              ..orderBy([(t) => OrderingTerm.asc(t.sort)]))
            .get();
    return rows
        .map((r) => PosFloor(id: r.id, name: r.name, sort: r.sort))
        .toList();
  }

  Future<void> saveTables(String tenantId, List<PosTable> rows) =>
      _db.transaction(() async {
        await (_db.delete(
          _db.cachedTables,
        )..where((t) => t.tenantId.equals(tenantId))).go();
        await _db.batch((b) {
          for (final t in rows) {
            b.insert(
              _db.cachedTables,
              CachedTablesCompanion.insert(
                tenantId: tenantId,
                id: t.id,
                label: t.label,
                capacity: t.capacity,
                state: t.state,
                floorId: Value(t.floorId),
                currentOrderId: Value(t.currentOrderId),
              ),
              mode: InsertMode.insertOrReplace,
            );
          }
        });
        await _stamp(tenantId);
      });

  Future<List<PosTable>> tables(String tenantId) async {
    final rows =
        await (_db.select(_db.cachedTables)
              ..where((t) => t.tenantId.equals(tenantId))
              ..orderBy([(t) => OrderingTerm.asc(t.label)]))
            .get();
    return rows
        .map(
          (r) => PosTable(
            id: r.id,
            label: r.label,
            capacity: r.capacity,
            state: r.state,
            floorId: r.floorId,
            currentOrderId: r.currentOrderId,
          ),
        )
        .toList();
  }

  /// Merge a stock change into the cached menu, so a dish that went sold out
  /// while the app was open is still sold out after a cold start.
  Future<void> setCachedItem86(
    String tenantId,
    String itemId,
    bool is86,
  ) async {
    await (_db.update(_db.cachedMenuItems)
          ..where((t) => t.tenantId.equals(tenantId) & t.id.equals(itemId)))
        .write(CachedMenuItemsCompanion(is86: Value(is86)));
  }

  /// Merge one Realtime row change into the cached board, so the next cold
  /// start doesn't show a state the waiter already watched change.
  Future<void> upsertTable(String tenantId, PosTable table) => _db
      .into(_db.cachedTables)
      .insertOnConflictUpdate(
        CachedTable(
          tenantId: tenantId,
          id: table.id,
          label: table.label,
          capacity: table.capacity,
          state: table.state,
          floorId: table.floorId,
          currentOrderId: table.currentOrderId,
        ),
      );
}
