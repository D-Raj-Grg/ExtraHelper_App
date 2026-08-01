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
/// * Offline with something cached → serve the cache, attempt nothing.
/// * Offline with an empty cache → attempt anyway. An empty cache is not an
///   answer, and the attempt's failure is what tells the user why.
/// * Online → attempt, but no longer than [timeout]; a failure or an overrun
///   falls back to the cache, and only an empty cache lets the error through.
///
/// [cached] returns null for "nothing cached" — an empty list of memberships
/// is absence, not an answer.
Future<T> cacheBackedRead<T>({
  required Future<bool> Function() isOnline,
  required Future<T> Function() fetch,
  required Future<T?> Function() cached,
  Duration timeout = const Duration(seconds: 6),
  Duration connectivityTimeout = const Duration(seconds: 2),
}) async {
  // An unanswered or broken connectivity check is treated as online: attempt
  // the read and let its own cap decide, rather than serving stale data on a
  // hunch. The check must never become the thing that blocks.
  var online = true;
  try {
    online = await isOnline().timeout(connectivityTimeout);
  } on Object {
    online = true;
  }

  if (!online) {
    final fallback = await cached();
    if (fallback != null) return fallback;
  }

  try {
    return await fetch().timeout(timeout);
  } on Object {
    final fallback = await cached();
    if (fallback != null) return fallback;
    rethrow;
  }
}
