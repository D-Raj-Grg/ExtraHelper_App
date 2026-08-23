import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/supabase/preferences_repository.dart';
import '../prefs.dart';

/// Which palette the app paints in.
///
/// **Two tiers, in this order: device first, account second.** The device's
/// stored value is what paints the first frame, because a staff app must render
/// its own theme on dead wifi and cannot wait on a query to know what colour it
/// is. `user_preferences` — the same row the web app writes — is then read and
/// adopted, so a new phone opens looking like the laptop its owner set up on.
///
/// A choice made on this device always wins over a value still arriving from
/// the server; [_settled] is what enforces that, and it is set by the first of
/// either to land.
///
/// **The default is light, not the OS.** Both palettes are first-class, but a
/// phone set to switch itself at sunset must not repaint the till in the middle
/// of service. Following the system is offered, never assumed.
///
/// [ThemeMode.system] is deliberately **not** synced: the column checks
/// `('light','dark')` and the web has no System option, so a phone following
/// its OS simply leaves the stored value alone rather than inventing a third
/// value the web could not read.
const _themeModeKey = 'theme_mode';

/// Stored as a plain string so the value survives a rename of Flutter's enum
/// and reads sensibly if anyone ever inspects the prefs file.
String _encode(ThemeMode mode) => switch (mode) {
  ThemeMode.light => 'light',
  ThemeMode.dark => 'dark',
  ThemeMode.system => 'system',
};

/// Anything unrecognised — written by an older build, or corrupt — falls back
/// to the default rather than throwing. This runs during startup, so an
/// exception here would take the whole app down over a preference.
ThemeMode _decode(String? raw) => switch (raw) {
  'dark' => ThemeMode.dark,
  'system' => ThemeMode.system,
  _ => ThemeMode.light,
};

class AppThemeMode extends Notifier<ThemeMode> {
  /// Whether a stored value has had its say — the same guard [PrintEnabled]
  /// carries. SharedPreferences resolves a frame or two after launch, so
  /// without this a choice made in between is silently overwritten when it
  /// lands and the setting appears to change itself.
  bool _settled = false;

  /// Whether the person using this device has chosen since launch. Separate
  /// from [_settled] because the account's value may arrive *after* the
  /// device's, and it must not undo a tap that happened in between.
  bool _chosenHere = false;

  /// Completes once storage has been read, so a test (or a caller that wants to
  /// delay the first frame) can wait for the real value rather than the default.
  Future<void> get ready => ref.read(sharedPreferencesProvider.future);

  @override
  ThemeMode build() {
    ref.listen(sharedPreferencesProvider, (_, next) {
      final prefs = next.valueOrNull;
      if (prefs == null || _settled) return;
      _settled = true;
      final stored = prefs.getString(_themeModeKey);
      state = _decode(stored);
      // Nothing stored means this device has never been told. That is the one
      // case where the account's value is strictly better than the default, so
      // go and ask for it.
      if (stored == null) unawaited(_adoptAccountValue());
    }, fireImmediately: true);
    // Light while storage opens. Starting at `system` instead would paint the
    // first frame dark on a dark-mode phone and then snap to light.
    return ThemeMode.light;
  }

  Future<void> set(ThemeMode mode) async {
    // A deliberate choice outranks whatever is still loading from disk, and
    // anything still in flight from the server.
    _settled = true;
    _chosenHere = true;
    state = mode;
    final prefs = await ref.read(sharedPreferencesProvider.future);
    await prefs.setString(_themeModeKey, _encode(mode));

    // Best-effort, and silent either way: the device already looks right, and
    // an error about a preference failing to sync is noise at a till.
    final serverValue = _forServer(mode);
    if (serverValue == null) return;
    try {
      await ref.read(preferencesRepositoryProvider).save(theme: serverValue);
    } catch (_) {
      // Including "there is no Supabase client here at all", which is the case
      // in a widget test and on the very first frame after a cold start.
    }
  }

  /// Read what the account says and take it, unless this device has since had
  /// its own say.
  Future<void> _adoptAccountValue() async {
    final UserPrefs? prefs;
    try {
      prefs = await ref.read(preferencesRepositoryProvider).load();
    } catch (_) {
      return;
    }
    if (prefs == null || _chosenHere) return;
    final mode = _decode(prefs.theme);
    state = mode;
    final store = await ref.read(sharedPreferencesProvider.future);
    await store.setString(_themeModeKey, _encode(mode));
  }

  /// `system` has no server representation — see the note at the top of this
  /// file. Null means "leave the stored value alone".
  static String? _forServer(ThemeMode mode) => switch (mode) {
    ThemeMode.light => 'light',
    ThemeMode.dark => 'dark',
    ThemeMode.system => null,
  };
}

final themeModeProvider = NotifierProvider<AppThemeMode, ThemeMode>(
  AppThemeMode.new,
);

/// What each choice is called on screen. Enum values never reach staff.
String themeModeLabel(ThemeMode mode) => switch (mode) {
  ThemeMode.light => 'Light',
  ThemeMode.dark => 'Dark',
  ThemeMode.system => 'Follow system',
};
