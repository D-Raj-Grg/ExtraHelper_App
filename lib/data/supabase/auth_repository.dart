import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_providers.dart';

/// Thrown by [AuthRepository] with a message a user can act on.
///
/// The repository boundary never leaks `AuthException` — callers get this, so
/// no screen has to know what Supabase's error shapes look like.
class AuthFailure implements Exception {
  const AuthFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Sign-in and sign-out. Sign-up and restaurant creation stay on the web: those
/// are owner-at-a-desk tasks with currency, tax and branding steps, and porting
/// them would drag in email-confirm deep links for a flow that happens once.
class AuthRepository {
  const AuthRepository(this._client);

  final SupabaseClient _client;

  Session? get currentSession => _client.auth.currentSession;
  User? get currentUser => _client.auth.currentUser;

  Future<void> signIn({required String email, required String password}) async {
    final trimmed = email.trim();
    if (trimmed.isEmpty || password.isEmpty) {
      throw const AuthFailure('Enter your email and password.');
    }
    try {
      await _client.auth.signInWithPassword(email: trimmed, password: password);
    } on AuthException catch (e) {
      throw AuthFailure(friendlyAuthError(code: e.code, message: e.message));
    } catch (_) {
      throw const AuthFailure(
        "Couldn't reach the server. Check your connection and try again.",
      );
    }
  }

  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } catch (_) {
      // A failed sign-out still clears local state; surfacing an error here
      // would strand someone on a screen they're trying to leave.
    }
  }
}

/// Supabase's auth errors are terse. Mirrors the web's `friendlyAuthError`
/// (`app/auth/actions.ts`) so the same failure reads the same on both clients.
String friendlyAuthError({String? code, required String message}) {
  final c = code ?? '';
  final m = message.toLowerCase();

  if (c == 'invalid_credentials' ||
      m.contains('invalid login credentials') ||
      m.contains('invalid_credentials')) {
    return 'That email or password is wrong.';
  }
  if (c == 'email_not_confirmed' || m.contains('not confirmed')) {
    return 'Confirm your email first — check your inbox for the link.';
  }
  if (c == 'email_address_invalid' ||
      (m.contains('email') && m.contains('invalid'))) {
    return 'That email address was rejected. Some domains (e.g. .dev, .local, '
        "disposable addresses) aren't accepted — try another email.";
  }
  if (c == 'user_already_exists' || m.contains('already registered')) {
    return 'An account with this email already exists. Try signing in instead.';
  }
  if (c == 'weak_password' || m.contains('password')) {
    return 'That password was rejected. Use at least 8 characters with a mix of '
        'letters and numbers.';
  }
  if (c == 'over_request_rate_limit' || m.contains('rate limit')) {
    return 'Too many attempts. Wait a minute and try again.';
  }
  return message;
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(supabaseProvider)),
);
