import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_providers.dart';

/// The appearance the web app remembers for this person.
class UserPrefs {
  const UserPrefs({required this.theme, required this.textScale});

  /// `light` or `dark`. The column checks exactly those two — there is no
  /// `system` on the server, and see `AppThemeMode` for what the phone does
  /// about that.
  final String theme;

  /// 0..4, indexing the web's 14/15/16/18/20px type scale.
  final int textScale;

  static UserPrefs fromJson(Map<String, dynamic> json) => UserPrefs(
    theme: json['theme'] as String? ?? 'light',
    textScale: switch (json['text_scale']) {
      int n => n.clamp(0, 4),
      num n => n.round().clamp(0, 4),
      _ => 2,
    },
  );
}

/// `user_preferences`, shared with the web app.
///
/// **Every method here swallows its failures and returns null.** Appearance is
/// not worth an error state: the device's own stored value is always good
/// enough to paint with, and a phone on dead wifi must still start in the right
/// palette. The server is a nicety that makes a new device feel familiar, not a
/// source of truth this app waits on.
class PreferencesRepository {
  const PreferencesRepository(this._client);

  final SupabaseClient _client;

  String? get _userId => _client.auth.currentUser?.id;

  Future<UserPrefs?> load() async {
    final userId = _userId;
    if (userId == null) return null;
    try {
      final row = await _client
          .from('user_preferences')
          .select('theme, text_scale')
          .eq('user_id', userId)
          .maybeSingle();
      return row == null ? null : UserPrefs.fromJson(row);
    } catch (_) {
      return null;
    }
  }

  /// Returns whether it landed, so a caller can decide whether to re-read —
  /// nobody currently needs to, and nothing is shown to the user either way.
  Future<bool> save({String? theme, int? textScale}) async {
    final userId = _userId;
    if (userId == null) return false;
    if (theme != null && theme != 'light' && theme != 'dark') return false;
    if (theme == null && textScale == null) return true;
    try {
      await _client.from('user_preferences').upsert({
        'user_id': userId,
        // Null-aware entries: an absent value leaves the stored one alone,
        // which is what makes this safe to call with only one of the two.
        'theme': ?theme,
        if (textScale != null) 'text_scale': textScale.clamp(0, 4),
      }, onConflict: 'user_id');
      return true;
    } catch (_) {
      return false;
    }
  }
}

final preferencesRepositoryProvider = Provider<PreferencesRepository>(
  (ref) => PreferencesRepository(ref.watch(supabaseProvider)),
);
