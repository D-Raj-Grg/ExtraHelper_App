import 'package:extrahelper/app/redirect.dart';
import 'package:extrahelper/app/router.dart';
import 'package:extrahelper/data/supabase/tenant_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _member = Membership(
  tenantId: 't1',
  name: 'The Sekuwa Station',
  slug: 'the-sekuwa-station',
  role: 'owner',
  currency: 'NPR',
  timezone: 'Asia/Kathmandu',
);

void main() {
  group('signed out', () {
    test('goes to login, and stays there', () {
      expect(
        resolveRedirect(
          signedIn: false,
          memberships: const AsyncValue.data(null),
          permissions: null,
          location: Routes.home,
        ),
        Routes.login,
      );
      expect(
        resolveRedirect(
          signedIn: false,
          memberships: const AsyncValue.data(null),
          permissions: null,
          location: Routes.login,
        ),
        isNull,
      );
    });
  });

  group('membership is not an answer yet', () {
    // The bug this guards: an owner of a live restaurant opened 1.0.8 on a
    // restored session and was shown "Join a restaurant" while the server was
    // answering 200 with their membership on every request.
    test('null memberships hold position rather than claiming /join', () {
      expect(
        resolveRedirect(
          signedIn: true,
          memberships: const AsyncValue.data(null),
          permissions: null,
          location: Routes.home,
        ),
        isNull,
      );
    });

    test('a failed read holds position rather than claiming /join', () {
      expect(
        resolveRedirect(
          signedIn: true,
          memberships: AsyncValue.error(Exception('offline'), StackTrace.empty),
          permissions: null,
          location: Routes.home,
        ),
        isNull,
      );
    });

    test('still loading with nothing yet holds position', () {
      expect(
        resolveRedirect(
          signedIn: true,
          memberships: const AsyncValue<List<Membership>?>.loading(),
          permissions: null,
          location: Routes.home,
        ),
        isNull,
      );
    });
  });

  group('genuinely no restaurant', () {
    test('an empty list — and only an empty list — sends you to /join', () {
      expect(
        resolveRedirect(
          signedIn: true,
          memberships: const AsyncValue.data(<Membership>[]),
          permissions: null,
          location: Routes.home,
        ),
        Routes.join,
      );
      expect(
        resolveRedirect(
          signedIn: true,
          memberships: const AsyncValue.data(<Membership>[]),
          permissions: null,
          location: Routes.join,
        ),
        isNull,
      );
    });
  });

  group('in a restaurant', () {
    test('login and join are behind you', () {
      for (final loc in [Routes.login, Routes.join]) {
        expect(
          resolveRedirect(
            signedIn: true,
            memberships: const AsyncValue.data([_member]),
            permissions: const {'tables.view'},
            location: loc,
          ),
          Routes.home,
        );
      }
    });

    test('a kitchen-only role opens on the KDS, not a dead end', () {
      expect(
        resolveRedirect(
          signedIn: true,
          memberships: const AsyncValue.data([_member]),
          permissions: const {'kds.view', 'kds.bump'},
          location: Routes.home,
        ),
        Routes.kds,
      );
    });

    test('a POS role stays on the POS', () {
      expect(
        resolveRedirect(
          signedIn: true,
          memberships: const AsyncValue.data([_member]),
          permissions: const {'tables.view', 'kds.view'},
          location: Routes.home,
        ),
        isNull,
      );
    });
  });

  group('signing up happens before there is a session', () {
    // Signup and email verification are the only two screens that must work
    // with no session at all. Before in-app signup existed the signed-out rule
    // was "anywhere but /login → /login", which would bounce someone out of
    // signup the instant they got there.
    test('signup is reachable signed out', () {
      expect(
        resolveRedirect(
          signedIn: false,
          memberships: const AsyncValue.data(null),
          permissions: null,
          location: Routes.signup,
        ),
        isNull,
      );
    });

    test('email verification is reachable signed out', () {
      expect(
        resolveRedirect(
          signedIn: false,
          memberships: const AsyncValue.data(null),
          permissions: null,
          location: Routes.verify,
        ),
        isNull,
      );
    });

    test('everything else still bounces to login', () {
      for (final location in [Routes.home, Routes.join, Routes.kds]) {
        expect(
          resolveRedirect(
            signedIn: false,
            memberships: const AsyncValue.data(null),
            permissions: null,
            location: location,
          ),
          Routes.login,
          reason: '$location should not be reachable signed out',
        );
      }
    });

    test('a verified user with no restaurant lands on onboarding', () {
      expect(
        resolveRedirect(
          signedIn: true,
          memberships: const AsyncValue.data([]),
          permissions: null,
          location: Routes.verify,
        ),
        Routes.join,
      );
    });

    test('signup and verify are behind a user who has a restaurant', () {
      for (final location in [Routes.signup, Routes.verify]) {
        expect(
          resolveRedirect(
            signedIn: true,
            memberships: const AsyncValue.data([_member]),
            permissions: null,
            location: location,
          ),
          Routes.home,
          reason: '$location should be behind an onboarded user',
        );
      }
    });
  });
}
