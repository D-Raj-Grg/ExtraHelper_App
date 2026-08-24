import 'package:extrahelper/core/prefs.dart';
import 'package:extrahelper/features/welcome/welcome_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The first-launch flag.
///
/// Unlike every other preference in the app this one is read **synchronously**,
/// because the router's redirect is synchronous and runs before the first
/// frame. `main()` resolves SharedPreferences before `runApp` and overrides the
/// provider with the instance; these tests do the same thing by hand.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(ProviderContainer, SharedPreferences)> containerWith(
    Map<String, Object> stored,
  ) async {
    SharedPreferences.setMockInitialValues(stored);
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWith((ref) => prefs)],
    );
    addTearDown(c.dispose);
    return (c, prefs);
  }

  test('the override is data on the first read, with nothing pumped', () async {
    // The whole no-flash property rests on this: a create function that returns
    // a value rather than a Future is `AsyncData` immediately. If Riverpod ever
    // stops doing that, this fails here rather than as a flicker on a phone.
    final (c, prefs) = await containerWith({});
    expect(c.read(sharedPreferencesProvider).valueOrNull, same(prefs));
  });

  test('a fresh install has not seen it', () async {
    final (c, _) = await containerWith({});
    expect(c.read(welcomeSeenProvider), isFalse);
  });

  test('a device that has seen it is left alone', () async {
    final (c, _) = await containerWith({'welcome_seen': true});
    expect(c.read(welcomeSeenProvider), isTrue);
  });

  // The safety net. A test — or any future caller — that forgets the override
  // must get "seen", never "show it again": an unknown may not interrupt
  // someone who is already typing a password.
  test('storage that never resolves reads as seen', () {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(welcomeSeenProvider), isTrue);
  });

  test('marking it seen flips state now and lands on disk after', () async {
    final (c, prefs) = await containerWith({});
    final write = c.read(welcomeSeenProvider.notifier).markSeen();

    // Synchronously true, before the write completes — this is what moves the
    // router on the frame of the tap.
    expect(c.read(welcomeSeenProvider), isTrue);

    await write;
    expect(prefs.getBool('welcome_seen'), isTrue);
  });

  test('marking it seen twice does not write twice', () async {
    final (c, _) = await containerWith({'welcome_seen': true});
    await c.read(welcomeSeenProvider.notifier).markSeen();
    expect(c.read(welcomeSeenProvider), isTrue);
  });
}
