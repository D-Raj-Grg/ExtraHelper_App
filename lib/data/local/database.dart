import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

/// Every cached table carries its `tenantId`. **The cache is tenant-stamped**
/// (`CLAUDE.md` rule 2): switching restaurant wipes and refetches, so one
/// tenant's menu can never render under another's name.
mixin _TenantScoped on Table {
  TextColumn get tenantId => text()();
}

class CacheMeta extends Table {
  TextColumn get tenantId => text()();
  DateTimeColumn get fetchedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {tenantId};
}

class CachedCategories extends Table with _TenantScoped {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get sort => integer()();

  @override
  Set<Column<Object>> get primaryKey => {tenantId, id};
}

class CachedMenuItems extends Table with _TenantScoped {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get basePriceCents => integer()();
  TextColumn get categoryId => text().nullable()();
  BoolColumn get is86 => boolean()();

  /// Nullable on purpose — "unmarked" is a real state that must render nothing.
  BoolColumn get isVeg => boolean().nullable()();
  TextColumn get imageUrl => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {tenantId, id};
}

class CachedVariants extends Table with _TenantScoped {
  TextColumn get id => text()();
  TextColumn get itemId => text()();
  TextColumn get name => text()();
  IntColumn get priceDeltaCents => integer()();

  @override
  Set<Column<Object>> get primaryKey => {tenantId, id};
}

class CachedModifiers extends Table with _TenantScoped {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get priceCents => integer()();

  @override
  Set<Column<Object>> get primaryKey => {tenantId, id};
}

/// The `item_modifiers` links. Cached separately for the same reason the web
/// keeps them: the server rejects any add-on not linked to *this* dish, so a
/// tenant-wide list would build a picker whose choices get refused.
class CachedItemModifiers extends Table with _TenantScoped {
  TextColumn get itemId => text()();
  TextColumn get modifierId => text()();

  @override
  Set<Column<Object>> get primaryKey => {tenantId, itemId, modifierId};
}

class CachedFloors extends Table with _TenantScoped {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get sort => integer()();

  @override
  Set<Column<Object>> get primaryKey => {tenantId, id};
}

class CachedTables extends Table with _TenantScoped {
  TextColumn get id => text()();
  TextColumn get label => text()();
  IntColumn get capacity => integer()();
  TextColumn get state => text()();
  TextColumn get floorId => text().nullable()();
  TextColumn get currentOrderId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {tenantId, id};
}

/// Who the signed-in user is, and where.
///
/// Cached because a cold start with no coverage otherwise renders "no ordering
/// access": memberships and permissions are network reads, and without them the
/// shell has no tenant and no keys. A waiter restarting their phone mid-service
/// must find the app exactly as they left it.
///
/// Not a security boundary — the server enforces every one of these keys inside
/// the RPCs. This only decides what is drawn.
class CachedMemberships extends Table {
  TextColumn get tenantId => text()();
  TextColumn get name => text()();
  TextColumn get slug => text()();
  TextColumn get role => text()();
  TextColumn get currency => text()();
  TextColumn get timezone => text()();
  IntColumn get sortIndex => integer()();

  @override
  Set<Column<Object>> get primaryKey => {tenantId};
}

class CachedPermissions extends Table with _TenantScoped {
  TextColumn get key => text()();

  @override
  Set<Column<Object>> get primaryKey => {tenantId, key};
}

/// The store room, for reading with no coverage.
///
/// A walk-in freezer or a back store room is exactly where the signal dies, and
/// a count is a job you walk into a room to do. This holds enough to list and
/// search what needs counting; the counted numbers themselves go through the
/// outbox.
class CachedInventoryItems extends Table with _TenantScoped {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get uom => text()();
  TextColumn get category => text().nullable()();
  RealColumn get currentQty => real()();
  RealColumn get reorderLevel => real()();
  IntColumn get costCents => integer()();

  /// Null for most items — the scanner falls back to search.
  TextColumn get barcode => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {tenantId, id};
}

/// The write path. One row per owed write.
class OutboxRows extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get tenantId => text()();
  TextColumn get kind => text()();
  TextColumn get orderRef => text()();
  TextColumn get payloadJson => text()();

  /// Unique: a double-enqueue must collapse to one row, or one tap becomes two
  /// orders.
  TextColumn get idempotencyKey => text().unique()();

  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get state => text()();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
}

@DriftDatabase(
  tables: [
    CacheMeta,
    CachedCategories,
    CachedMenuItems,
    CachedVariants,
    CachedModifiers,
    CachedItemModifiers,
    CachedFloors,
    CachedTables,
    CachedMemberships,
    CachedPermissions,
    CachedInventoryItems,
    OutboxRows,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// An in-memory database, for tests.
  AppDatabase.memory() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 3;

  /// v2 added the identity cache, v3 the store room. A phone that already has an
  /// older file is upgraded in place — dropping the file would take the outbox
  /// with it, and the outbox may be holding a real order.
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(cachedMemberships);
        await m.createTable(cachedPermissions);
      }
      if (from < 3) {
        await m.createTable(cachedInventoryItems);
      }
    },
  );
}

/// Opens the on-disk database. The outbox lives here, so this file surviving a
/// crash is the whole point of rule 4.
Future<AppDatabase> openAppDatabase() async {
  final dir = await getApplicationDocumentsDirectory();
  final file = File(p.join(dir.path, 'extrahelper.sqlite'));
  return AppDatabase(NativeDatabase.createInBackground(file));
}
