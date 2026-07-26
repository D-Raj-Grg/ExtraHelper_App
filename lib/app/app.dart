import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// App root. Theme, routing, and the auth-gated shell land in Milestones B and
/// C (see `TASKS.md`); this is the scaffold that proves the native Supabase
/// wiring works on both platforms.
class ExtraHelperApp extends StatelessWidget {
  const ExtraHelperApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ExtraHelper',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1F6F4A)),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1F6F4A),
          brightness: Brightness.dark,
        ),
      ),
      home: const _ScaffoldCheckScreen(),
    );
  }
}

/// Temporary. Confirms `Supabase.initialize` succeeded and the client can reach
/// the project — replaced by the login screen in Milestone C.
class _ScaffoldCheckScreen extends StatelessWidget {
  const _ScaffoldCheckScreen();

  @override
  Widget build(BuildContext context) {
    final session = Supabase.instance.client.auth.currentSession;
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('ExtraHelper', style: theme.textTheme.headlineMedium),
                const SizedBox(height: 8),
                Text(
                  'Supabase client initialised',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                Text(
                  session == null
                      ? 'No session — sign-in lands in Milestone C.'
                      : 'Signed in as ${session.user.email}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
