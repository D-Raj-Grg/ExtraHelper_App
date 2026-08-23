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

/// Sign-in, sign-up, email verification and sign-out.
///
/// Signup used to live only on the web because confirming an email meant a
/// link, and a link meant Universal Links, App Links and a signed domain file
/// for a flow that happens once per account. Verifying with a **code the user
/// types** removes that entirely — same email, same Supabase setting, no
/// URL scheme anywhere in the app.
///
/// The confirmation email must render `{{ .Token }}` for that to work. It also
/// still renders the link, because the web flow continues to use it.
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

    await claimInvites();
  }

  /// Create an account. Returns `true` when Supabase handed back a session,
  /// meaning email confirmation is off and the user is already in; `false`
  /// means a code is on its way and the caller must collect it.
  ///
  /// Both are real configurations and the caller must handle each — reading
  /// the project's current setting into the app would make this break silently
  /// the day someone changes it in the dashboard.
  ///
  /// `full_name` feeds the `profiles` row through the `handle_new_user`
  /// trigger; `restaurant_name` is read back to prefill onboarding. Same two
  /// keys the web sends (`app/auth/actions.ts`).
  Future<bool> signUp({
    required String email,
    required String password,
    String fullName = '',
    String restaurantName = '',
  }) async {
    final trimmed = email.trim();
    if (trimmed.isEmpty || password.isEmpty) {
      throw const AuthFailure('Enter your email and a password.');
    }
    try {
      final res = await _client.auth.signUp(
        email: trimmed,
        password: password,
        data: {
          if (fullName.trim().isNotEmpty) 'full_name': fullName.trim(),
          if (restaurantName.trim().isNotEmpty)
            'restaurant_name': restaurantName.trim(),
        },
      );
      return res.session != null;
    } on AuthException catch (e) {
      throw AuthFailure(friendlyAuthError(code: e.code, message: e.message));
    } catch (_) {
      throw const AuthFailure(
        "Couldn't reach the server. Check your connection and try again.",
      );
    }
  }

  /// Exchange the emailed code for a session. On success the user is signed in,
  /// so the router takes over from here exactly as it does after a password
  /// sign-in.
  Future<void> verifySignupOtp({
    required String email,
    required String token,
  }) async {
    final trimmedEmail = email.trim();
    final trimmedToken = token.trim();
    if (trimmedEmail.isEmpty || trimmedToken.isEmpty) {
      throw const AuthFailure('Enter the code we emailed you.');
    }
    final AuthResponse res;
    try {
      res = await _client.auth.verifyOTP(
        type: OtpType.signup,
        email: trimmedEmail,
        token: trimmedToken,
      );
    } on AuthException catch (e) {
      throw AuthFailure(friendlyAuthError(code: e.code, message: e.message));
    } catch (_) {
      throw const AuthFailure(
        "Couldn't reach the server. Check your connection and try again.",
      );
    }

    // `verifyOTP` does not throw when it accepts a token without issuing a
    // session — that is how the two-step email-change flow reports "first of
    // two codes accepted". Signup should never land there, but if it did the
    // router would have nothing to react to and the screen would sit looking
    // like the button did nothing. Say so instead of stalling in silence.
    if (res.session == null) {
      throw const AuthFailure(
        'That code was accepted but did not sign you in. Try signing in with '
        'your email and password.',
      );
    }

    await claimInvites();
  }

  /// Send the confirmation email again. Rate limited server-side, and
  /// [friendlyAuthError] turns that limit into something better than a raw
  /// message — someone who taps twice deserves to be told to wait, not to see
  /// a stack of red.
  Future<void> resendSignupOtp({required String email}) async {
    final trimmed = email.trim();
    if (trimmed.isEmpty) throw const AuthFailure('Enter your email.');
    try {
      await _client.auth.resend(type: OtpType.signup, email: trimmed);
    } on AuthException catch (e) {
      throw AuthFailure(friendlyAuthError(code: e.code, message: e.message));
    } catch (_) {
      throw const AuthFailure(
        "Couldn't reach the server. Check your connection and try again.",
      );
    }
  }

  /// Attach any staff invite sent to this user's email as a pending membership.
  ///
  /// Best-effort on purpose. The web calls this after every sign-in
  /// (`app/auth/actions.ts`) and the app never did, so someone invited by email
  /// who only ever opened the phone app was left on the join screen with a code
  /// they were never given. Failing here must not block a sign-in that already
  /// succeeded — the join screen offers a manual retry.
  Future<void> claimInvites() async {
    try {
      await _client.rpc('claim_invites');
    } catch (_) {
      // Intentionally swallowed — see above.
    }
  }

  /// Delete the signed-in user's account, then clear local state.
  ///
  /// The server refuses while the caller is the sole owner of a restaurant;
  /// that message is meant to be shown as-is, because it tells the user what to
  /// do about it.
  Future<void> deleteAccount() async {
    try {
      await _client.rpc('delete_my_account');
    } on PostgrestException catch (e) {
      throw AuthFailure(
        e.code == '28000' ? "You're signed out — sign in again." : e.message,
      );
    } catch (_) {
      throw const AuthFailure(
        "Couldn't reach the server. Check your connection and try again.",
      );
    }
    await signOut();
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
