import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The one handle on device storage.
///
/// Three features keep a preference on the device — the active restaurant, the
/// print-from-this-device switch, the palette — and each used to declare its own
/// private copy of this provider. Three copies means three `getInstance()`
/// calls, three futures resolving at different moments, and a test that mocks
/// storage for one of them silently leaves the others reading the real thing.
///
/// `SharedPreferences.getInstance()` is itself a singleton behind the scenes, so
/// this is about having one *provider* to override, not one instance.
final sharedPreferencesProvider = FutureProvider<SharedPreferences>(
  (ref) => SharedPreferences.getInstance(),
);
