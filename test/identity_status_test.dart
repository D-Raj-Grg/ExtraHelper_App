import 'dart:async';

import 'package:extrahelper/data/supabase/tenant_repository.dart';
import 'package:extrahelper/features/tenant/tenant_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the shell knows about who this person is — and the difference between
/// not knowing and knowing the answer is nothing.
///
/// The bug these exist for: `permissionsProvider` answered `const {}` whenever
/// the active tenant had not resolved. An empty set reads to all 43 permission
/// gates as "loaded, and you may do nothing", so on a weak signal the drawer
/// emptied, the POS never appeared, and the shell sat on a spinner with no way
/// out — the app looked as though the waiter had been stripped of access. The
/// identity cache was never the problem; the answer given while waiting for it
/// was.

const _member = Membership(
  tenantId: 't1',
  name: 'The Sekuwa Station',
  slug: 'the-sekuwa-station',
  role: 'waiter',
  currency: 'NPR',
  timezone: 'Asia/Kathmandu',
);

ProviderContainer _containerWith({
  required AsyncValue<List<Membership>?> memberships,
  AsyncValue<Set<String>>? permissions,
}) {
  final c = ProviderContainer(
    overrides: [
      // Returned synchronously where there is a value, so the state is real on
      // the first read rather than a frame later — the same property `main()`
      // relies on when it injects SharedPreferences.
      membershipsProvider.overrideWith(
        (ref) => switch (memberships) {
          AsyncData(:final value) => value,
          AsyncError(:final error) => throw error,
          _ => Completer<List<Membership>?>().future,
        },
      ),
      if (permissions != null)
        permissionsProvider.overrideWith(
          (ref) => switch (permissions) {
            AsyncData(:final value) => value,
            AsyncError(:final error) => throw error,
            _ => Completer<Set<String>>().future,
          },
        ),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('permissions never answer for a tenant that has not resolved', () {
    // The regression test for the whole bug.
    test('memberships still loading leaves permissions unresolved', () async {
      final c = _containerWith(
        memberships: const AsyncValue<List<Membership>?>.loading(),
      );

      c.listen(permissionsProvider, (_, _) {});
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final perms = c.read(permissionsProvider);
      expect(
        perms.hasValue,
        isFalse,
        reason: 'an empty set here reads as "you may do nothing"',
      );
      expect(perms.isLoading, isTrue);
    });

    test('memberships not known yet leaves permissions unresolved', () async {
      final c = _containerWith(memberships: const AsyncValue.data(null));

      c.listen(permissionsProvider, (_, _) {});
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(c.read(permissionsProvider).hasValue, isFalse);
    });

    // The one case where an empty set IS the answer.
    test('a user in no restaurant genuinely holds no keys', () async {
      final c = _containerWith(
        memberships: const AsyncValue<List<Membership>?>.data([]),
      );

      c.listen(permissionsProvider, (_, _) {});
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(c.read(permissionsProvider).valueOrNull, isEmpty);
    });
  });

  group('identity status', () {
    test('unknown while memberships are still resolving', () {
      final c = _containerWith(
        memberships: const AsyncValue<List<Membership>?>.loading(),
        permissions: const AsyncValue.loading(),
      );
      expect(c.read(identityStatusProvider), IdentityStatus.unknown);
    });

    test('unknown when memberships resolve but permissions have not', () {
      final c = _containerWith(
        memberships: const AsyncValue<List<Membership>?>.data([_member]),
        permissions: const AsyncValue.loading(),
      );
      expect(c.read(identityStatusProvider), IdentityStatus.unknown);
    });

    test('noRestaurant only for a real, empty list', () {
      final c = _containerWith(
        memberships: const AsyncValue<List<Membership>?>.data([]),
        permissions: const AsyncValue.data({}),
      );
      expect(c.read(identityStatusProvider), IdentityStatus.noRestaurant);
    });

    test('a failed read outranks everything — it has a recovery', () {
      final failed = AsyncValue<Set<String>>.error(
        Exception('no route to host'),
        StackTrace.empty,
      );
      final c = _containerWith(
        memberships: const AsyncValue<List<Membership>?>.data([_member]),
        permissions: failed,
      );
      expect(c.read(identityStatusProvider), IdentityStatus.unavailable);
      expect(c.read(identityErrorProvider), isNotNull);
    });

    test('ready only when both have answered', () {
      final c = _containerWith(
        memberships: const AsyncValue<List<Membership>?>.data([_member]),
        permissions: const AsyncValue.data({'order.create'}),
      );
      expect(c.read(identityStatusProvider), IdentityStatus.ready);
    });
  });

  group('the fail-closed contract, pinned', () {
    // Actions stay denied while unknown. That is deliberate and must not be
    // "fixed" into optimism: a control that appears late is fine, one that
    // vanishes under a thumb already moving is not. Surfaces read the status
    // instead; actions keep reading this.
    test('a permission is false in every state that is not ready', () {
      for (final permissions in [
        const AsyncValue<Set<String>>.loading(),
        AsyncValue<Set<String>>.error(Exception('offline'), StackTrace.empty),
        const AsyncValue<Set<String>>.data({}),
      ]) {
        final c = _containerWith(
          memberships: const AsyncValue<List<Membership>?>.data([_member]),
          permissions: permissions,
        );
        expect(c.read(hasPermissionProvider('order.create')), isFalse);
      }
    });
  });
}
