import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;

import 'package:extrahelper/data/local/database.dart';
import 'package:extrahelper/data/local/identity_cache.dart';
import 'package:extrahelper/data/supabase/supabase_providers.dart';
import 'package:extrahelper/data/supabase/tenant_repository.dart';
import 'package:extrahelper/data/sync/connectivity.dart';
import 'package:extrahelper/data/sync/sync_providers.dart';
import 'package:extrahelper/features/tenant/tenant_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Stale-while-revalidate for the identity reads: a warm cache is served the
/// moment it is read and the network refreshes behind it.
///
/// What this protects is the shell. Before, a phone on wifi with a dead line
/// read as online, took the network path, and held the whole app on a spinner
/// for the warm cap (2s) twice over — once for memberships, once for
/// permissions — even though the answer was sitting in sqlite. The cache is for
/// rendering only; every RPC still enforces the same keys.

const _a = Membership(
  tenantId: 'tenant-a',
  name: 'Cafe A',
  slug: 'cafe-a',
  role: 'waiter',
  currency: 'NPR',
  timezone: 'Asia/Kathmandu',
);
const _b = Membership(
  tenantId: 'tenant-b',
  name: 'Cafe B',
  slug: 'cafe-b',
  role: 'manager',
  currency: 'NPR',
  timezone: 'Asia/Kathmandu',
);
final _aPromoted = Membership(
  tenantId: _a.tenantId,
  name: _a.name,
  slug: _a.slug,
  role: 'manager',
  currency: _a.currency,
  timezone: _a.timezone,
);

/// A repository whose every read is a completer the test resolves by hand, so
/// "the network has not answered yet" is a state a test can sit in.
class _FakeRepo implements TenantRepository {
  final membershipReads = <Completer<List<Membership>>>[];
  final permissionReads = <String, List<Completer<Set<String>>>>{};

  @override
  Future<List<Membership>> activeMemberships() {
    final c = Completer<List<Membership>>();
    membershipReads.add(c);
    return c.future;
  }

  @override
  Future<Set<String>> permissions(String tenantId) {
    final c = Completer<Set<String>>();
    (permissionReads[tenantId] ??= []).add(c);
    return c.future;
  }

  int permissionCalls(String tenantId) =>
      permissionReads[tenantId]?.length ?? 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

extension on List<Completer<List<Membership>>> {
  /// Answers every read still outstanding: a rebuild (connectivity settling)
  /// may have started a second one, and the first is then discarded.
  void answer(List<Membership> v) {
    for (final c in this) {
      if (!c.isCompleted) c.complete(v);
    }
  }
}

class _FakeConnectivity extends ConnectivityWatcher {
  _FakeConnectivity({required this.online});

  bool online;
  final changes = StreamController<bool>.broadcast();

  @override
  Future<bool> isOnline() async => online;

  @override
  Stream<bool> get onChange => changes.stream;

  void go(bool value) {
    online = value;
    changes.add(value);
  }
}

class _Rig {
  _Rig({bool online = true})
    : db = AppDatabase.memory(),
      repo = _FakeRepo(),
      net = _FakeConnectivity(online: online) {
    SharedPreferences.setMockInitialValues({});
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        tenantRepositoryProvider.overrideWithValue(repo),
        connectivityProvider.overrideWithValue(net),
        authStateProvider.overrideWith((ref) => const Stream<Session?>.empty()),
        currentUserProvider.overrideWithValue(
          User(
            id: 'user-1',
            appMetadata: const {},
            userMetadata: const {},
            aud: 'authenticated',
            createdAt: '2026-01-01T00:00:00Z',
          ),
        ),
      ],
    );
  }

  final AppDatabase db;
  final _FakeRepo repo;
  final _FakeConnectivity net;
  late final ProviderContainer container;

  IdentityCache get cache => IdentityCache(db);

  /// Keeps both providers alive and lets the event queue drain.
  Future<void> start() async {
    container.listen(membershipsProvider, (_, _) {});
    container.listen(permissionsProvider, (_, _) {});
    await pumpEventQueue();
  }

  Future<void> dispose() async {
    container.dispose();
    await net.changes.close();
    await db.close();
  }
}

Future<_Rig> _rig({bool online = true}) async {
  final rig = _Rig(online: online);
  addTearDown(rig.dispose);
  return rig;
}

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  group('memberships', () {
    test(
      'a warm cache renders at once, without waiting on the network',
      () async {
        final rig = await _rig();
        await rig.cache.saveMemberships([_a]);

        rig.container.listen(membershipsProvider, (_, _) {});
        // The repo never answers. Nothing here may depend on it.
        final value = await rig.container
            .read(membershipsProvider.future)
            .timeout(const Duration(milliseconds: 500));

        expect(value!.single.tenantId, 'tenant-a');
        expect(rig.repo.membershipReads, isNotEmpty, reason: 'refresh began');
      },
    );

    test(
      'the background refresh updates what is shown, and the cache',
      () async {
        final rig = await _rig();
        await rig.cache.saveMemberships([_a]);
        await rig.start();

        expect(
          rig.container.read(membershipsProvider).value!.single.role,
          'waiter',
        );

        final readsBefore = rig.repo.membershipReads.length;
        rig.repo.membershipReads.answer([_aPromoted]);
        await pumpEventQueue();

        expect(
          rig.container.read(membershipsProvider).value!.single.role,
          'manager',
        );
        expect((await rig.cache.memberships()).single.role, 'manager');
        expect(
          rig.repo.membershipReads,
          hasLength(readsBefore),
          reason: 'applying the refresh must not trigger another one',
        );
      },
    );

    test('an unchanged answer does not churn the provider', () async {
      final rig = await _rig();
      await rig.cache.saveMemberships([_a]);
      var emissions = 0;
      rig.container.listen(membershipsProvider, (_, _) => emissions++);
      await pumpEventQueue();
      final before = emissions;

      rig.repo.membershipReads.answer([_a]);
      await pumpEventQueue();

      expect(emissions, before);
    });

    test('a failed refresh keeps the cached answer, with no error', () async {
      final rig = await _rig();
      await rig.cache.saveMemberships([_a]);
      await rig.start();

      rig.repo.membershipReads.first.completeError(StateError('no route'));
      await pumpEventQueue();

      final state = rig.container.read(membershipsProvider);
      expect(state.hasError, isFalse);
      expect(state.value!.single.tenantId, 'tenant-a');
      expect((await rig.cache.memberships()).single.tenantId, 'tenant-a');
    });

    test('offline with a warm cache serves it and attempts nothing', () async {
      final rig = await _rig(online: false);
      await rig.cache.saveMemberships([_a]);
      await rig.start();

      expect(rig.container.read(membershipsProvider).value, isNotNull);
      expect(rig.repo.membershipReads, isEmpty);
    });

    test('coverage returning refreshes behind the cache once', () async {
      final rig = await _rig(online: false);
      await rig.cache.saveMemberships([_a]);
      await rig.start();
      expect(rig.repo.membershipReads, isEmpty);

      rig.net.go(true);
      await pumpEventQueue();
      expect(rig.repo.membershipReads, hasLength(1));

      rig.repo.membershipReads.answer([_aPromoted]);
      await pumpEventQueue();

      expect(
        rig.container.read(membershipsProvider).value!.single.role,
        'manager',
      );
      expect(rig.repo.membershipReads, hasLength(1));
    });

    test(
      'a cold cache still waits for the network, and says why it failed',
      () async {
        final rig = await _rig();
        rig.container.listen(membershipsProvider, (_, _) {});
        // Let connectivity settle first: its first event rebuilds the provider.
        await pumpEventQueue();
        final read = rig.container.read(membershipsProvider.future);
        await pumpEventQueue();

        expect(rig.repo.membershipReads, isNotEmpty);
        rig.repo.membershipReads.answer([_a]);
        expect((await read)!.single.tenantId, 'tenant-a');
        expect((await rig.cache.memberships()), hasLength(1));

        final cold = await _rig();
        cold.container.listen(membershipsProvider, (_, _) {});
        await pumpEventQueue();
        final failing = cold.container.read(membershipsProvider.future);
        final expectation = expectLater(failing, throwsStateError);
        await pumpEventQueue();
        for (final c in cold.repo.membershipReads) {
          if (!c.isCompleted) c.completeError(StateError('down'));
        }
        await expectation;
      },
    );
  });

  group('permissions', () {
    Future<_Rig> warm({Set<String> keys = const {'orders.create'}}) async {
      final rig = await _rig();
      await rig.cache.saveMemberships([_a, _b]);
      await rig.cache.savePermissions('tenant-a', keys);
      return rig;
    }

    test(
      'a warm cache renders at once, without waiting on the network',
      () async {
        final rig = await warm();
        await rig.start();

        expect(rig.container.read(permissionsProvider).value, {
          'orders.create',
        });
        expect(rig.repo.permissionCalls('tenant-a'), 1);
      },
    );

    test(
      'the background refresh updates what is shown, and the cache',
      () async {
        final rig = await warm();
        await rig.start();

        rig.repo.permissionReads['tenant-a']!.single.complete({
          'orders.create',
          'orders.void',
        });
        await pumpEventQueue();

        expect(rig.container.read(permissionsProvider).value, {
          'orders.create',
          'orders.void',
        });
        expect(await rig.cache.permissions('tenant-a'), {
          'orders.create',
          'orders.void',
        });
        expect(rig.repo.permissionCalls('tenant-a'), 1);
      },
    );

    test('a refresh that revokes a key takes effect', () async {
      final rig = await warm(keys: {'orders.create', 'orders.void'});
      await rig.start();

      rig.repo.permissionReads['tenant-a']!.single.complete({'orders.create'});
      await pumpEventQueue();

      expect(rig.container.read(permissionsProvider).value, {'orders.create'});
    });

    test('a failed refresh keeps the cached keys, with no error', () async {
      final rig = await warm();
      await rig.start();

      rig.repo.permissionReads['tenant-a']!.single.completeError(
        StateError('no route'),
      );
      await pumpEventQueue();

      final state = rig.container.read(permissionsProvider);
      expect(state.hasError, isFalse);
      expect(state.value, {'orders.create'});
      expect(await rig.cache.permissions('tenant-a'), {'orders.create'});
    });

    test('a user who holds no keys is an answer, served at once', () async {
      final rig = await warm(keys: const {});
      await rig.start();

      expect(rig.container.read(permissionsProvider).value, <String>{});
    });
  });

  group('a tenant switch never leaks the old tenant', () {
    test(
      'serves the new tenant\'s cache, never the old tenant\'s keys',
      () async {
        final rig = await _rig();
        await rig.cache.saveMemberships([_a, _b]);
        await rig.cache.savePermissions('tenant-a', {'a.only'});
        await rig.cache.savePermissions('tenant-b', {'b.only'});
        await rig.start();
        await rig.container
            .read(activeTenantSelectionProvider.notifier)
            .select('tenant-a');
        await pumpEventQueue();
        expect(rig.container.read(permissionsProvider).value, {'a.only'});

        await rig.container
            .read(activeTenantSelectionProvider.notifier)
            .select('tenant-b');
        await pumpEventQueue();

        expect(rig.container.read(permissionsProvider).value, {'b.only'});
      },
    );

    test('a refresh for the old tenant landing late changes nothing', () async {
      final rig = await _rig();
      await rig.cache.saveMemberships([_a, _b]);
      await rig.cache.savePermissions('tenant-a', {'a.only'});
      await rig.cache.savePermissions('tenant-b', {'b.only'});
      await rig.start();
      final selection = rig.container.read(
        activeTenantSelectionProvider.notifier,
      );
      await selection.select('tenant-a');
      await pumpEventQueue();

      await selection.select('tenant-b');
      await pumpEventQueue();
      // Tenant A's refresh was already in flight when the switch happened.
      rig.repo.permissionReads['tenant-a']!.first.complete({'a.late'});
      await pumpEventQueue();

      expect(rig.container.read(permissionsProvider).value, {'b.only'});
      expect(
        await rig.cache.permissions('tenant-b'),
        {'b.only'},
        reason: 'tenant B\'s rows are untouched by tenant A\'s answer',
      );
    });
  });
}
