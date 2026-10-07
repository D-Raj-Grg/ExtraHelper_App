import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:extrahelper/data/local/database.dart';
import 'package:extrahelper/data/local/identity_cache.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/schema_v4.dart' as v4;

/// The v4 → v5 upgrade, run for real.
///
/// `drift_dev`'s SchemaVerifier cannot be used in this dependency graph:
/// drift_dev 2.34.0 (the newest the Flutter SDK's pinned `meta` allows) does
/// not compile against drift 2.34.2 (`GeneratedDatabase.schema` is missing).
/// So `support/schema_v4.dart` is a frozen copy of the v4 database, generated
/// like any other Drift file; this test builds a real v4 sqlite file with it,
/// then opens that same file with the current [AppDatabase] and lets
/// `onUpgrade` run.
///
/// A phone upgrading in place matters because the outbox may hold a real
/// order, and dropping the file to "fix" a migration would lose it.
void main() {
  // Two databases on purpose: the migrated one and a fresh one to compare to.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('migration_test');
    file = File('${dir.path}/extrahelper.sqlite');
  });

  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> seedV4() async {
    final old = v4.AppDatabaseV4(NativeDatabase(file));
    await old
        .into(old.outboxRows)
        .insert(
          v4.OutboxRowsCompanion.insert(
            tenantId: 'tenant-a',
            kind: 'place_order',
            orderRef: 'order-1',
            payloadJson: '{"items":2}',
            idempotencyKey: 'key-1',
            state: 'pending',
            createdAt: DateTime(2026, 8, 1),
          ),
        );
    await old
        .into(old.cachedVariants)
        .insert(
          v4.CachedVariantsCompanion.insert(
            tenantId: 'tenant-a',
            id: 'var-1',
            itemId: 'item-1',
            name: 'Large',
            priceDeltaCents: 300,
            sort: const Value(7),
          ),
        );
    await old
        .into(old.cachedMemberships)
        .insert(
          v4.CachedMembershipsCompanion.insert(
            tenantId: 'tenant-a',
            name: 'Test Cafe',
            slug: 'test-cafe',
            role: 'waiter',
            currency: 'NPR',
            timezone: 'Asia/Kathmandu',
            sortIndex: 0,
          ),
        );
    await old
        .into(old.cachedPermissions)
        .insert(
          v4.CachedPermissionsCompanion.insert(
            tenantId: 'tenant-a',
            key: 'orders.create',
          ),
        );
    expect(old.schemaVersion, 4);
    await old.close();
  }

  Future<Set<String>> tableNames(AppDatabase db) async {
    final rows = await db
        .customSelect(
          "select name from sqlite_master where type = 'table' "
          "and name not like 'sqlite_%'",
        )
        .get();
    return rows.map((r) => r.read<String>('name')).toSet();
  }

  Future<Map<String, List<String>>> columnsByTable(AppDatabase db) async {
    final out = <String, List<String>>{};
    for (final t in await tableNames(db)) {
      final cols = await db.customSelect('pragma table_info("$t")').get();
      out[t] = cols
          .map(
            (c) =>
                '${c.read<String>('name')} ${c.read<String>('type')} '
                'notnull=${c.read<int>('notnull')} pk=${c.read<int>('pk')}',
          )
          .toList();
    }
    return out;
  }

  test('a v4 file is really v4 before it is opened', () async {
    await seedV4();
    // Guards the fixture: if it ever stopped producing a v4 file the upgrade
    // test below would pass without exercising onUpgrade at all.
    final before = v4.AppDatabaseV4(NativeDatabase(file));
    final version = await before
        .customSelect('pragma user_version')
        .getSingle();
    expect(version.read<int>('user_version'), 4);
    expect(
      (await before
              .customSelect(
                'select name from sqlite_master '
                "where name = 'cached_permission_meta'",
              )
              .get())
          .isEmpty,
      isTrue,
    );
    await before.close();
  });

  test('upgrades v4 to v5 in place and keeps the data', () async {
    await seedV4();

    final db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);

    // Opening runs onUpgrade lazily; touch the database.
    final outbox = await db.select(db.outboxRows).get();

    expect(outbox, hasLength(1), reason: 'the outbox must survive in place');
    expect(outbox.single.idempotencyKey, 'key-1');
    expect(outbox.single.payloadJson, '{"items":2}');
    expect(outbox.single.state, 'pending');

    final variant = await db.select(db.cachedVariants).getSingle();
    expect(variant.id, 'var-1');
    expect(variant.sort, 7);

    final cache = IdentityCache(db);
    final memberships = await cache.memberships();
    expect(memberships.single.name, 'Test Cafe');
    expect(await cache.permissions('tenant-a'), {'orders.create'});

    final version = await db.customSelect('pragma user_version').getSingle();
    expect(version.read<int>('user_version'), 5);
  });

  test('the new marker table exists, is empty, and is writable', () async {
    await seedV4();
    final db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);

    expect(await tableNames(db), contains('cached_permission_meta'));
    expect(await db.select(db.cachedPermissionMeta).get(), isEmpty);

    final cache = IdentityCache(db);
    await cache.savePermissions('tenant-a', {});
    // The point of the marker: a genuinely empty set is now an answer.
    expect(await cache.permissionsIfFetched('tenant-a'), <String>{});
  });

  test(
    'permissions cached before v5 read as never-fetched, not as an answer',
    () async {
      await seedV4();
      final db = AppDatabase(NativeDatabase(file));
      addTearDown(db.close);

      // Rows from v4 carry no marker, so the first online read refetches rather
      // than trusting keys that predate the marker's guarantee.
      expect(await IdentityCache(db).permissionsIfFetched('tenant-a'), isNull);
    },
  );

  test('the upgraded schema matches a freshly created v5 database', () async {
    await seedV4();
    final upgraded = AppDatabase(NativeDatabase(file));
    addTearDown(upgraded.close);
    final fresh = AppDatabase.memory();
    addTearDown(fresh.close);

    expect(await columnsByTable(upgraded), await columnsByTable(fresh));
  });

  test('upgrading adds the variant sort default for a v3 -> v5 path', () async {
    // v3 lacked cached_variants.sort. Simulate it by dropping the column on a
    // v4 file and stamping version 3, then make sure addColumn restores it.
    await seedV4();
    final raw = v4.AppDatabaseV4(NativeDatabase(file));
    await raw.customStatement('alter table cached_variants drop column sort');
    await raw.customStatement('pragma user_version = 3');
    await raw.close();

    final db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);

    final variant = await db.select(db.cachedVariants).getSingle();
    expect(variant.name, 'Large');
    expect(variant.sort, 0, reason: 'default for rows that predate the column');
    expect(await tableNames(db), contains('cached_permission_meta'));
  });
}
