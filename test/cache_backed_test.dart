import 'package:extrahelper/data/local/cache_backed.dart';
import 'package:flutter_test/flutter_test.dart';

/// The shell's identity reads — memberships and permissions — go through this.
///
/// The bug it exists for: with an expired access token, every Supabase call
/// first awaits a token refresh, and gotrue retries that refresh with backoff
/// until the next delay would outrun its 10s auto-refresh tick. Offline the
/// refresh can never succeed, so a cold start sat on a spinner for ~13 seconds
/// on the emulator before anything consulted the cache that exists for exactly
/// this case. A read must never block the shell.

void main() {
  group('offline', () {
    test('serves the cache without touching the network', () async {
      var fetched = false;

      final result = await cacheBackedRead<String>(
        isOnline: () async => false,
        fetch: () async {
          fetched = true;
          return 'fresh';
        },
        cached: () async => 'cached',
      );

      expect(result, 'cached');
      expect(fetched, isFalse, reason: 'offline must not attempt the network');
    });

    test('still tries the network when there is nothing cached', () async {
      final result = await cacheBackedRead<String>(
        isOnline: () async => false,
        fetch: () async => 'fresh',
        cached: () async => null,
      );

      // An empty cache is not an answer, so the attempt is all we have — and
      // its failure is what tells the user something is wrong.
      expect(result, 'fresh');
    });
  });

  group('online', () {
    test('returns the server answer', () async {
      final result = await cacheBackedRead<String>(
        isOnline: () async => true,
        fetch: () async => 'fresh',
        cached: () async => 'cached',
      );

      expect(result, 'fresh');
    });

    test('falls back to the cache when the read outruns the cap', () async {
      final result = await cacheBackedRead<String>(
        isOnline: () async => true,
        fetch: () =>
            Future<String>.delayed(const Duration(seconds: 30), () => 'fresh'),
        cached: () async => 'cached',
        timeout: const Duration(milliseconds: 50),
      );

      expect(result, 'cached');
    });

    test('falls back to the cache when the read throws', () async {
      final result = await cacheBackedRead<String>(
        isOnline: () async => true,
        fetch: () async => throw StateError('no route to host'),
        cached: () async => 'cached',
      );

      expect(result, 'cached');
    });

    test('surfaces the failure when there is nothing to fall back to', () {
      expect(
        cacheBackedRead<String>(
          isOnline: () async => true,
          fetch: () async => throw StateError('no route to host'),
          cached: () async => null,
        ),
        throwsStateError,
      );
    });
  });

  group('the connectivity check itself', () {
    test('never becomes the thing that blocks', () async {
      final result = await cacheBackedRead<String>(
        isOnline: () =>
            Future<bool>.delayed(const Duration(seconds: 30), () => false),
        fetch: () async => 'fresh',
        cached: () async => 'cached',
        connectivityTimeout: const Duration(milliseconds: 50),
      );

      // Unanswered connectivity is treated as online: attempt the read, and let
      // its own cap and its own failure decide, rather than serving stale data
      // on a hunch.
      expect(result, 'fresh');
    });

    test('a thrown connectivity check is treated the same way', () async {
      final result = await cacheBackedRead<String>(
        isOnline: () async => throw StateError('no platform channel'),
        fetch: () async => 'fresh',
        cached: () async => 'cached',
      );

      expect(result, 'fresh');
    });
  });
}
