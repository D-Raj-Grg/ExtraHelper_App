import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'core/env.dart';
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

  runApp(
    ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      // Two loops, one app: `SyncLoop` owes the server writes, `PrintLoop` owes
      // the kitchen paper. Both are mounted above the router so neither depends
      // on which screen happens to be open.
      child: const SyncLoop(child: PrintLoop(child: ExtraHelperApp())),
    ),
  );
}
