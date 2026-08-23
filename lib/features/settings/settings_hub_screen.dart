import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_scaffold.dart';
import '../../app/router.dart';
import '../../core/theme/tokens.dart';
import '../tenant/tenant_providers.dart';

/// Everything the web app's Settings tabs cover, as a list of doors.
///
/// The web puts six tabs inside one `<form>` — twenty-odd fields behind a single
/// Save button. That works at a desk; on a 360dp phone it is six screens of
/// scrolling and one place to lose a keystroke. Here each surface is its own
/// pushed screen with its own save, its own permission, and its own set of
/// providers to invalidate afterwards.
class SettingsHubScreen extends ConsumerWidget {
  const SettingsHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenant = ref.watch(activeTenantProvider);
    // Read the permission set itself rather than `hasPermissionProvider`, which
    // answers false while it loads. On a screen made entirely of gated rows,
    // false-while-loading draws an empty page that then pops rows in.
    final permissions = ref.watch(permissionsProvider);
    final isOwner = tenant?.role == 'owner';
    final isManager = ref.watch(isManagerProvider);

    return AppScaffold(
      title: 'Settings',
      subtitle: tenant?.name,
      body: permissions.when(
        loading: () => const _LoadingRows(),
        error: (e, _) => _Problem(message: '$e', onRetry: () => ref.invalidate(permissionsProvider)),
        data: (perms) {
          final canSee = perms.contains('settings.view');
          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              if (canSee) ...[
                const _SectionLabel('Restaurant'),
                const _SettingsRow(
                  icon: Icons.storefront_outlined,
                  label: 'General',
                  detail: 'Name, currency, timezone, day start',
                  route: Routes.settingsGeneral,
                ),
                const _SettingsRow(
                  icon: Icons.receipt_long_outlined,
                  label: 'Charges & tax',
                  detail: 'Service charge, packaging fee, tax rules',
                  route: Routes.settingsCharges,
                ),
                const _SettingsRow(
                  icon: Icons.description_outlined,
                  label: 'Receipt & branding',
                  detail: 'Header, footer, logo, payment QR',
                  route: Routes.settingsReceipt,
                ),
                const _SettingsRow(
                  icon: Icons.location_on_outlined,
                  label: 'Branches',
                  detail: 'Where this restaurant trades',
                  route: Routes.settingsBranches,
                ),
                const _SettingsRow(
                  icon: Icons.print_outlined,
                  label: 'Printers',
                  detail: 'The registry, as the web set it up',
                  route: Routes.settingsPrinters,
                ),
                if (isManager)
                  const _SettingsRow(
                    icon: Icons.workspace_premium_outlined,
                    label: 'Plan & usage',
                    detail: 'What this restaurant is using',
                    route: Routes.settingsPlan,
                  ),
              ],
              const _SectionLabel('This device'),
              const _SettingsRow(
                icon: Icons.print_disabled_outlined,
                label: 'Printing from this device',
                detail: 'Whether this phone drives printers',
                route: Routes.printing,
              ),
              const _SettingsRow(
                icon: Icons.palette_outlined,
                label: 'Appearance',
                detail: 'Light, dark, text size',
                route: Routes.settingsAppearance,
              ),
              const _SectionLabel('You'),
              const _SettingsRow(
                icon: Icons.badge_outlined,
                label: 'Profile',
                detail: 'Your name and handle',
                route: Routes.settingsProfile,
              ),
              const _SettingsRow(
                icon: Icons.person_outline,
                label: 'Account & permissions',
                detail: 'Who you are signed in as',
                route: Routes.account,
              ),
              if (isOwner) ...[
                const _SectionLabel('Danger'),
                const _SettingsRow(
                  icon: Icons.warning_amber_outlined,
                  label: 'Dangerous area',
                  detail: 'Reset, transfer ownership, delete',
                  route: Routes.settingsDanger,
                  danger: true,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.label,
    required this.detail,
    required this.route,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final String detail;
  final String route;

  /// Tints the glyph only. The word "Dangerous area" and the subtitle carry the
  /// meaning, so the row still reads in greyscale.
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      minTileHeight: Tokens.tapTarget + 12,
      leading: Icon(icon, color: danger ? theme.colorScheme.error : null),
      title: Text(label),
      subtitle: Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right),
      // Leaves push: back returns here, not to the POS.
      onTap: () => context.push(route),
    );
  }
}

/// Rows in outline while permissions load. Placeholders rather than an empty
/// list so the screen does not visibly grow under the thumb about to tap it.
class _LoadingRows extends StatelessWidget {
  const _LoadingRows();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.only(top: 8),
      children: List.generate(
        5,
        (_) => ListTile(
          minTileHeight: Tokens.tapTarget + 12,
          leading: Icon(
            Icons.circle_outlined,
            color: theme.colorScheme.surfaceContainerHighest,
          ),
          title: Container(
            height: 14,
            width: 160,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(Tokens.radiusSm),
            ),
          ),
        ),
      ),
    );
  }
}

class _Problem extends StatelessWidget {
  const _Problem({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 36),
            const SizedBox(height: 12),
            Text(
              "Couldn't check what you're allowed to change.",
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
