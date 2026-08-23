import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'pos_repository.dart' show PosFailure, PosTransientFailure;
import 'supabase_providers.dart';

/// Who the signed-in person is, across every restaurant they work in.
class Profile {
  const Profile({this.fullName, this.username, this.avatarUrl});

  final String? fullName;
  final String? username;
  final String? avatarUrl;

  static Profile fromJson(Map<String, dynamic> json) => Profile(
    fullName: _text(json['full_name']),
    username: _text(json['username']),
    avatarUrl: _text(json['avatar_url']),
  );

  static String? _text(Object? value) {
    final raw = (value as String?)?.trim() ?? '';
    return raw.isEmpty ? null : raw;
  }
}

/// A handle is lowercase letters, digits and underscores. Same shape the web
/// uses, so a name claimed on one client is spelled the same on the other.
final _handleRe = RegExp(r'^[a-z0-9_]{3,30}$');

/// The signed-in user's own profile row.
///
/// **The only repository here with no tenant id.** `profiles` has no
/// `tenant_id` column — a person is one person whichever restaurant they are
/// standing in — so the usual defence-in-depth `.eq('tenant_id', …)` has
/// nothing to attach to. `profiles_self` RLS keys on `auth.uid()` instead, and
/// the id below comes from the same session.
class ProfileRepository {
  const ProfileRepository(this._client);

  final SupabaseClient _client;

  String? get _userId => _client.auth.currentUser?.id;

  Future<Profile?> load() async {
    final userId = _userId;
    if (userId == null) return null;
    try {
      final row = await _client
          .from('profiles')
          .select('full_name, username, avatar_url')
          .eq('id', userId)
          .maybeSingle();
      return row == null ? const Profile() : Profile.fromJson(row);
    } on PostgrestException catch (e) {
      throw PosFailure(e.message);
    } catch (_) {
      throw const PosTransientFailure("Couldn't load your profile.");
    }
  }

  /// Upsert rather than update: a user who signed up before the profile trigger
  /// existed has no row, and a screen that saves nothing with no error is worse
  /// than one that creates the row.
  Future<void> save({String? fullName, String? username}) async {
    final userId = _userId;
    if (userId == null) {
      throw const PosFailure('Sign in again to change your profile.');
    }
    final name = fullName?.trim() ?? '';
    if (name.length > 80) {
      throw const PosFailure('That name is too long.');
    }
    final handle = username?.trim().toLowerCase() ?? '';
    if (handle.isNotEmpty && !_handleRe.hasMatch(handle)) {
      throw const PosFailure(
        'A handle is 3 to 30 characters: lowercase letters, numbers and '
        'underscores.',
      );
    }
    try {
      await _client.from('profiles').upsert({
        'id': userId,
        'full_name': name.isEmpty ? null : name,
        'username': handle.isEmpty ? null : handle,
      }, onConflict: 'id');
    } on PostgrestException catch (e) {
      // 23505 is the unique index on `username`. Anything else is the server's
      // own sentence, which is more specific than one made up here.
      throw PosFailure(
        e.code == '23505' ? 'That handle is already taken.' : e.message,
      );
    } catch (_) {
      throw const PosTransientFailure("Couldn't save your profile just now.");
    }
  }
}

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => ProfileRepository(ref.watch(supabaseProvider)),
);
