import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/theme_mode_provider.dart';
import 'router.dart';

/// App root: the ported theme (Milestone B) plus the auth-gated router
/// (Milestone C).
///
/// Light and dark are both first-class, and which one shows is the staff
/// member's choice — held per device and defaulting to **light** rather than
/// the OS, so a phone set to darken itself at sunset cannot repaint the till
/// mid-service. Account → Appearance offers "Follow system" for anyone who
/// wants the platform behaviour back.
class ExtraHelperApp extends ConsumerWidget {
  const ExtraHelperApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'ExtraHelper',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
