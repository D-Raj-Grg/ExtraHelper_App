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

  /// The captive-portal case, and the reason the cache is read first.
  ///
  /// `connectivity_plus` reports whether an interface exists, not whether it
  /// goes anywhere. A phone on restaurant wifi with a dead line reads as online
  /// and takes the network path — so what bounds the wait has to be whether we
  /// already hold a truthful answer, not what the interface claims.
  group('a warm cache is not worth waiting on', () {
    test('caps the read far shorter than a cold one would', () async {
      final started = DateTime.now();

      final result = await cacheBackedRead<String>(
        isOnline: () async => true,
        fetch: () =>
            Future<String>.delayed(const Duration(seconds: 30), () => 'fresh'),
        cached: () async => 'cached',
        warmTimeout: const Duration(milliseconds: 50),
      );

      expect(result, 'cached');
      expect(
        DateTime.now().difference(started),
        lessThan(const Duration(seconds: 5)),
        reason: 'a warm read must not sit out the cold cap',
      );
    });

    test('an explicitly shorter cap still wins', () async {
      // The caller asked for 50ms and meant it; the warm cap must not lengthen
      // a read that someone deliberately tightened.
      final result = await cacheBackedRead<String>(
        isOnline: () async => true,
        fetch: () =>
            Future<String>.delayed(const Duration(seconds: 30), () => 'fresh'),
        cached: () async => 'cached',
        timeout: const Duration(milliseconds: 50),
        warmTimeout: const Duration(seconds: 2),
      );

      expect(result, 'cached');
    });

    test('a cold cache still gets the full cap', () async {
      // Nothing to serve, so the attempt is all there is — cutting it short
      // would only turn a slow answer into no answer.
      final result = await cacheBackedRead<String>(
        isOnline: () async => true,
        fetch: () => Future<String>.delayed(
          const Duration(milliseconds: 120),
          () => 'fresh',
        ),
        cached: () async => null,
        timeout: const Duration(seconds: 6),
        warmTimeout: const Duration(milliseconds: 10),
      );

      expect(result, 'fresh');
    });

    test('a warm cache still prefers a fresh answer that arrives', () async {
      final result = await cacheBackedRead<String>(
        isOnline: () async => true,
        fetch: () async => 'fresh',
        cached: () async => 'cached',
      );

      expect(result, 'fresh');
    });

    test('the cache is consulted exactly once', () async {
      var reads = 0;

      await cacheBackedRead<String>(
        isOnline: () async => true,
        fetch: () async => throw StateError('no route to host'),
        cached: () async {
          reads++;
          return 'cached';
        },
      );

      // It used to be read once in the offline branch and again in the catch.
      // Reading it once is what lets it decide the cap before the attempt.
      expect(reads, 1);
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
