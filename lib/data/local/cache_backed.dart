import 'dart:async';

/// Read the server's answer without letting that read block the shell.
///
/// The shape this exists for, measured on the Android emulator in airplane
/// mode with an expired access token: `supabase` awaits a token refresh before
/// *every* request when the session has expired
/// (`supabase_client.dart::_getAccessToken`), and gotrue retries that refresh
/// with backoff until the next delay would outrun its 10-second auto-refresh
/// tick. With no coverage the refresh can never succeed, so the POS sat on a
/// spinner for about thirteen seconds before anything consulted the identity
/// cache that exists for exactly this case. A waiter whose phone sat idle
/// overnight and opens the app in a basement hits it every time.
///
/// The rule, the same one the offline bugs in Milestone F all came down to:
/// **ask connectivity first, and cap the wait even when the answer is yes.**
///
/// **Ask the cache first of all, though.** `connectivity_plus` only reports
/// whether an interface exists, so a phone on restaurant wifi whose line is
/// down reads as *online* — it takes the network path and pays the full cap,
/// twice over as the shell reads memberships and then permissions. The cache is
/// a sub-millisecond sqlite read and it cannot lie about whether an answer
/// exists, so it, not the interface state, decides how long we are willing to
/// wait:
///
/// * Offline with something cached → serve the cache, attempt nothing.
/// * Offline with an empty cache → attempt anyway. An empty cache is not an
///   answer, and the attempt's failure is what tells the user why.
/// * Online with something cached → attempt, but only for [warmTimeout]. We
///   already hold a truthful answer; the only thing at stake is freshness, and
///   freshness is not worth a spinner.
/// * Online with an empty cache → attempt for the full [timeout]. Here the wait
///   *is* the message, because its failure is what the user gets told.
///
/// An explicitly shorter [timeout] always wins over [warmTimeout] — a caller
/// that asked for a tighter cap meant it.
///
/// [cached] returns null for "nothing cached" — an empty list of memberships
/// is absence, not an answer. It is consulted exactly once per call.
Future<T> cacheBackedRead<T>({
  required Future<bool> Function() isOnline,
  required Future<T> Function() fetch,
  required Future<T?> Function() cached,
  Duration timeout = const Duration(seconds: 6),
  Duration warmTimeout = const Duration(seconds: 2),
  Duration connectivityTimeout = const Duration(seconds: 2),
}) async {
  final fallback = await cached();

  // An unanswered or broken connectivity check is treated as online: attempt
  // the read and let its own cap decide, rather than serving stale data on a
  // hunch. The check must never become the thing that blocks.
  var online = true;
  try {
    online = await isOnline().timeout(connectivityTimeout);
  } on Object {
    online = true;
  }

  if (!online && fallback != null) return fallback;

  final cap = fallback == null
      ? timeout
      : (timeout < warmTimeout ? timeout : warmTimeout);

  try {
    return await fetch().timeout(cap);
  } on Object {
    if (fallback != null) return fallback;
    rethrow;
  }
}

/// When a background refresh last ran for a key, so applying its answer cannot
/// start another one.
///
/// Applying a refresh rebuilds the provider that owns it, and the rebuild reads
/// the cache again and would refresh again, forever. The memo breaks that loop:
/// a key is refreshed at most once per [staleWhileRevalidate]'s `recently`
/// window. The key carries the connectivity state, so coverage coming back is a
/// new key and earns a fresh attempt.
class RefreshMemo {
  /// A time means finished then; otherwise in flight, owned by a build.
  final _entries = <Object, _Attempt>{};

  bool _blocks(Object key, DateTime now, Duration recently) {
    final a = _entries[key];
    if (a == null) return false;
    final at = a.finishedAt;
    // An attempt whose build was torn down will drop its answer, so it must
    // not stop the build that replaced it from asking again.
    return at == null ? a.owner() : now.difference(at) < recently;
  }
}

class _Attempt {
  _Attempt(this.owner, [this.finishedAt]);

  final bool Function() owner;
  final DateTime? finishedAt;
}

/// Serve the cache now, refresh behind it. The shape `_CachedList` already uses
/// for the menu, applied to the identity reads.
///
/// * **Warm cache, online** → returns the cached value immediately and starts a
///   background refresh. A changed answer is persisted and [onFresh] is called
///   (the provider invalidates itself, and the rebuild serves the new cache).
///   A failed or slow refresh changes nothing: the cache stays on screen.
/// * **Warm cache, offline** → the cache, and no attempt.
/// * **Cold cache** → waits for the network up to [coldTimeout], and its
///   failure surfaces; there the wait *is* the message.
///
/// Nothing here may be awaited on a tap, and the refresh never blocks the
/// caller. [isMounted] must turn false when the owning provider is torn down
/// (tenant switch, sign-out): a late answer is then dropped rather than
/// persisted, so it cannot write into — or resurrect — a cache that has moved
/// on. [fetch] must capture everything it needs at build time and never read
/// providers through a `ref` that may be gone.
Future<T> staleWhileRevalidate<T>({
  required RefreshMemo memo,
  required Object key,
  required Future<bool> Function() isOnline,
  required Future<T> Function() fetch,
  required Future<void> Function(T fresh) persist,
  required Future<T?> Function() cached,
  required bool Function(T a, T b) same,
  required bool Function() isMounted,
  required void Function() onFresh,
  Duration coldTimeout = const Duration(seconds: 6),
  Duration refreshTimeout = const Duration(seconds: 6),
  Duration connectivityTimeout = const Duration(seconds: 2),
  Duration recently = const Duration(seconds: 30),
  DateTime Function() now = DateTime.now,
}) async {
  final fallback = await cached();

  if (fallback == null) {
    // Nothing to show: an empty cache is not an answer, so attempt even when
    // offline — its failure is what tells the user why.
    final fresh = await fetch().timeout(coldTimeout);
    await persist(fresh);
    return fresh;
  }

  var online = true;
  try {
    online = await isOnline().timeout(connectivityTimeout);
  } on Object {
    online = true;
  }
  if (!online) return fallback;

  final memoKey = (key, online);
  if (memo._blocks(memoKey, now(), recently)) return fallback;
  memo._entries[memoKey] = _Attempt(isMounted);

  unawaited(() async {
    try {
      final fresh = await fetch().timeout(refreshTimeout);
      if (!isMounted()) {
        // Torn down mid-flight: drop the answer; the build that replaced this one asks again.
        return;
      }
      await persist(fresh);
      memo._entries[memoKey] = _Attempt(isMounted, now());
      if (isMounted() && !same(fresh, fallback)) onFresh();
    } on Object {
      // Keep the cache on screen. Stamped, so a failing network is retried
      // after the window rather than on every rebuild.
      memo._entries[memoKey] = _Attempt(isMounted, now());
    }
  }());

  return fallback;
}
