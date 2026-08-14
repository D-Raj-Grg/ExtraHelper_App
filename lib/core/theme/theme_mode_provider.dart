import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which palette the app paints in, held per device.
///
/// Per device rather than per account, like [printEnabledProvider]: the phone in
/// a waiter's apron and the tablet on the counter sit in very different light,
/// and they are often the same login.
///
/// **The default is light, not the OS.** Both palettes are first-class, but a
/// phone set to switch itself at sunset must not repaint the till in the middle
/// of service. Following the system is offered, never assumed.
const _themeModeKey = 'theme_mode';

final _prefsProvider = FutureProvider<SharedPreferences>(
  (ref) => SharedPreferences.getInstance(),
);

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
  /// Whether the stored value has had its say — the same guard
  /// [PrintEnabled] carries. SharedPreferences resolves a frame or two after
  /// launch, so without this a choice made in between is silently overwritten
  /// when it lands and the setting appears to change itself.
  bool _settled = false;

  /// Completes once storage has been read, so a test (or a caller that wants to
  /// delay the first frame) can wait for the real value rather than the default.
  Future<void> get ready => ref.read(_prefsProvider.future);

  @override
  ThemeMode build() {
    ref.listen(_prefsProvider, (_, next) {
      final prefs = next.valueOrNull;
      if (prefs == null || _settled) return;
      _settled = true;
      state = _decode(prefs.getString(_themeModeKey));
    }, fireImmediately: true);
    // Light while storage opens. Starting at `system` instead would paint the
    // first frame dark on a dark-mode phone and then snap to light.
    return ThemeMode.light;
  }

  Future<void> set(ThemeMode mode) async {
    // A deliberate choice outranks whatever is still loading from disk.
    _settled = true;
    state = mode;
    final prefs = await ref.read(_prefsProvider.future);
    await prefs.setString(_themeModeKey, _encode(mode));
  }
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
