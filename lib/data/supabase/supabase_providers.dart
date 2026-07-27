import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The one authenticated Supabase client. Everything data-related goes through
/// here, so RLS — keyed on the signed-in user — is the gate on every read and
/// write, exactly as it is on the web.
final supabaseProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

/// Auth state as a stream, so the router can react to a sign-in, a sign-out, or
/// a session that expired while the app was backgrounded.
///
/// Seeded with the current session: `onAuthStateChange` does emit an initial
/// event, but waiting for it would flash the login screen at a signed-in user
/// on every cold start.
final authStateProvider = StreamProvider<Session?>((ref) {
  final client = ref.watch(supabaseProvider);
  return client.auth.onAuthStateChange
      .map((event) => event.session)
      .distinct((a, b) => a?.accessToken == b?.accessToken);
});

/// The signed-in user, or null. Synchronous — reads the client's current
/// session rather than the stream, for call sites that can't await.
final currentUserProvider = Provider<User?>((ref) {
  // Watching the stream keeps this provider invalidated on sign-in/out.
  ref.watch(authStateProvider);
  return ref.watch(supabaseProvider).auth.currentUser;
});
