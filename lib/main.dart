import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'core/env.dart';
import 'core/prefs.dart';
import 'data/local/database.dart';
import 'data/print/print_providers.dart';
import 'data/sync/sync_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Env.assertConfigured();

  await Supabase.initialize(
    url: Env.supabaseUrl,
    publishableKey: Env.supabasePublishableKey,
  );

  // Opened before the first frame: the outbox may already hold writes from a
  // session that was killed mid-call, and they are owed before anything else
  // happens.
  final db = await openAppDatabase();

  // Also opened before the first frame, and for a sharper reason: the router's
  // redirect is **synchronous**. It runs before anything is painted and has to
  // answer "has this device seen the welcome carousel?" on the spot. Left to
  // resolve on its own, SharedPreferences lands a frame or two later — and the
  // app either flashes the login screen before the carousel or flashes the
  // carousel at someone who dismissed it months ago.
  //
  // Overriding the provider with the resolved instance makes every read of it
  // synchronous, here and everywhere else. Riverpod's `FutureProvider` treats a
  // create function that returns a value rather than a Future as data
  // immediately, with no microtask in between.
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sharedPreferencesProvider.overrideWith((ref) => prefs),
      ],
      // Two loops, one app: `SyncLoop` owes the server writes, `PrintLoop` owes
      // the kitchen paper. Both are mounted above the router so neither depends
      // on which screen happens to be open.
      child: const SyncLoop(child: PrintLoop(child: ExtraHelperApp())),
    ),
  );
}
