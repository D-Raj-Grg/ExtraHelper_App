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
