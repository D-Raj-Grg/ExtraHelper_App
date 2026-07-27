import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import 'router.dart';

/// App root: the ported theme (Milestone B) plus the auth-gated router
/// (Milestone C).
///
/// Light and dark are both first-class and follow the OS — the web ships a
/// per-user preference, which is the same promise honoured by the platform's
/// own control here.
class ExtraHelperApp extends ConsumerWidget {
  const ExtraHelperApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'ExtraHelper',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
