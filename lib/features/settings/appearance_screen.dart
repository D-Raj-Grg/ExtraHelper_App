import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_scaffold.dart';
import '../../core/theme/theme_mode_provider.dart';
import '../../core/widgets/choice_chip.dart';
import 'settings_form.dart';

/// How the app looks on this phone.
///
/// The palette is stored on the device *and* on the account: the device value
/// paints the first frame with no network, and a phone that has never been told
/// adopts whatever the web app was set to. A choice made here wins over both.
class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final theme = Theme.of(context);

    return AppScaffold(
      title: 'Appearance',
      showDrawer: false,
      body: ListView(
        padding: const EdgeInsets.only(top: 6, bottom: 24),
        children: [
          SettingsSection(
            title: 'Palette',
            detail:
                'Light unless you say otherwise, so a phone that darkens '
                'itself in the evening cannot change the till mid-service.',
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final mode in ThemeMode.values)
                    AppChoiceChip(
                      label: themeModeLabel(mode),
                      selected: themeMode == mode,
                      showCheck: true,
                      onSelect: () =>
                          ref.read(themeModeProvider.notifier).set(mode),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                themeMode == ThemeMode.system
                    // Worth saying plainly: someone who picks this and then
                    // wonders why the web app did not follow deserves an
                    // answer on the screen, not in a changelog.
                    ? 'Following the system is kept on this phone only — the '
                          'web app has no such setting to follow.'
                    : 'Saved to your account, so a new phone opens looking '
                          'like this one.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          SettingsSection(
            title: 'Text size',
            children: [
              Text(
                "This app follows your phone's own Display settings. Turn text "
                'size up there and every screen here grows with it.',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
