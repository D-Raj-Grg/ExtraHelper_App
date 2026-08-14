import 'package:extrahelper/core/theme/theme_mode_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Appearance is a per-device choice, held in SharedPreferences.
///
/// The default is **light, not the OS**: staff use this mid-service, and a
/// phone on scheduled dark mode must not repaint the till at dusk. Following
/// the system is available, but only when someone asks for it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> containerWith(Map<String, Object> stored) async {
    SharedPreferences.setMockInitialValues(stored);
    final c = ProviderContainer();
    addTearDown(c.dispose);
    // Let the FutureProvider holding SharedPreferences resolve.
    await c.read(themeModeProvider.notifier).ready;
    return c;
  }

  test('a fresh install is light, not the system setting', () async {
    final c = await containerWith({});
    expect(c.read(themeModeProvider), ThemeMode.light);
  });

  test('a stored choice is restored', () async {
    for (final (stored, expected) in [
      ('dark', ThemeMode.dark),
      ('light', ThemeMode.light),
      ('system', ThemeMode.system),
    ]) {
      final c = await containerWith({'theme_mode': stored});
      expect(c.read(themeModeProvider), expected, reason: 'stored: $stored');
    }
  });

  test('a value we do not recognise falls back to light', () async {
    // Written by an older or newer build, or simply corrupt. Falling back to
    // the default beats throwing at startup, which would take the app with it.
    final c = await containerWith({'theme_mode': 'sepia'});
    expect(c.read(themeModeProvider), ThemeMode.light);
  });

  test('choosing a mode persists it', () async {
    final c = await containerWith({});
    await c.read(themeModeProvider.notifier).set(ThemeMode.dark);
    expect(c.read(themeModeProvider), ThemeMode.dark);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('theme_mode'), 'dark');
  });

  test('a choice made before storage loads is not undone by it', () async {
    // The trap `PrintEnabled` already pays for: SharedPreferences resolves a
    // frame or two after launch, and without a settled flag it overwrites a
    // tap the user has already made — the switch flicks back on its own.
    SharedPreferences.setMockInitialValues({'theme_mode': 'system'});
    final c = ProviderContainer();
    addTearDown(c.dispose);

    c.read(themeModeProvider.notifier); // build, storage still in flight
    await c.read(themeModeProvider.notifier).set(ThemeMode.dark);
    await c.read(themeModeProvider.notifier).ready;

    expect(c.read(themeModeProvider), ThemeMode.dark);
  });
}
