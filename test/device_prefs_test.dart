import 'package:extrahelper/core/prefs.dart';
import 'package:extrahelper/core/theme/theme_mode_provider.dart';
import 'package:extrahelper/data/print/print_providers.dart';
import 'package:extrahelper/features/kds/kds_providers.dart';
import 'package:extrahelper/features/tenant/tenant_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Every per-device preference, restored the way the **app** restores them.
///
/// The bug these exist for, shipped in 1.0.12 and caught from the floor: each
/// of these notifiers adopted its stored value inside a
/// `ref.listen(..., fireImmediately: true)` callback and assigned it to
/// `state`. That works only while SharedPreferences resolves a frame or two
/// *after* launch — the first fire finds nothing and bails, and the real
/// assignment happens later, safely. When `main()` started pre-resolving
/// storage so the welcome gate could answer on the first frame, that first
/// fire arrived carrying data, the assignment landed *during* `build()` before
/// there was any state to assign to, and it went nowhere. Every one of these
/// settings silently reverted on every launch. Printing turned itself off
/// overnight and said nothing.
///
/// **The old tests all passed throughout**, because they built a container
/// without the override and exercised the slow path. These use the fast one —
/// the wiring `main()` actually ships.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Storage already resolved before the first read, exactly as `main()`
  /// arranges it.
  Future<ProviderContainer> live(Map<String, Object> stored) async {
    SharedPreferences.setMockInitialValues(stored);
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWith((ref) => prefs)],
    );
    addTearDown(c.dispose);
    return c;
  }

  group('a stored choice survives a relaunch', () {
    test('print from this device', () async {
      final c = await live({'print_from_this_device': true});
      expect(c.read(printEnabledProvider), isTrue);
    });

    test('appearance', () async {
      final c = await live({'theme_mode': 'dark'});
      expect(c.read(themeModeProvider), ThemeMode.dark);
    });

    test('the active restaurant', () async {
      final c = await live({'active_tenant_id': 't2'});
      expect(c.read(activeTenantSelectionProvider), 't2');
    });

    test('the kitchen station', () async {
      final c = await live({'kds_station': 'grill'});
      expect(c.read(kdsStationProvider), 'grill');
    });
  });

  group('nothing stored keeps the safe default', () {
    test('printing is off until someone says otherwise', () async {
      final c = await live({});
      expect(c.read(printEnabledProvider), isFalse);
    });

    test('appearance is light, not the OS', () async {
      final c = await live({});
      expect(c.read(themeModeProvider), ThemeMode.light);
    });
  });

  group('a tap outranks the disk', () {
    // The guard the original listener existed for, kept: a choice made while
    // storage is opening must not be undone when it lands.
    test('a choice made before storage resolves is not clobbered', () async {
      SharedPreferences.setMockInitialValues({'print_from_this_device': false});
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer();
      addTearDown(c.dispose);

      await c.read(printEnabledProvider.notifier).set(true);
      expect(c.read(printEnabledProvider), isTrue);

      // Storage lands afterwards with the old value; the tap stands.
      await c.read(sharedPreferencesProvider.future);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.read(printEnabledProvider), isTrue);
      expect(prefs.getBool('print_from_this_device'), isTrue);
    });
  });
}
