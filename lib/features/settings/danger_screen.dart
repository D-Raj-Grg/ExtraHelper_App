import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_scaffold.dart';
import '../../app/router.dart';
import '../../core/format/when.dart';
import '../../core/theme/tokens.dart';
import '../../data/supabase/danger_repository.dart';
import '../../data/supabase/pos_repository.dart' show PosFailure;
import '../tenant/tenant_providers.dart';
import 'confirm_phrase_dialog.dart';
import 'plan_usage_card.dart';
import 'settings_providers.dart';
import 'transfer_ownership_sheet.dart';

/// Reset, hand over, or end the restaurant.
///
/// Owner-only, and every RPC behind it re-checks that inside its own body — the
/// gate here is so nobody is shown a door they cannot open, not so the door is
/// locked.
///
/// It ships on a phone deliberately. The two things an owner most often needs
/// away from a desk are a reset (a botched import the night before opening) and
/// a transfer (handing a franchise over); the retype-the-name guard is what
/// makes that safe on a touch screen where a mis-tap costs nothing.
class DangerScreen extends ConsumerStatefulWidget {
  const DangerScreen({super.key});

  @override
  ConsumerState<DangerScreen> createState() => _DangerScreenState();
}

class _DangerScreenState extends ConsumerState<DangerScreen> {
  bool _busy = false;

  DangerRepository? get _repo {
    final tenant = ref.read(activeTenantProvider);
    if (tenant == null) return null;
    return ref.read(dangerRepositoryProvider(tenant.tenantId));
  }

  Future<void> _transfer(DangerData data) async {
    final tenantName = ref.read(activeTenantProvider)?.name ?? '';
    final member = await showTransferOwnershipSheet(
      context,
      members: data.members,
    );
    if (member == null || !mounted) return;

    final confirmed = await showConfirmPhraseDialog(
      context,
      title: 'Hand $tenantName to ${member.email}?',
      message:
          'They become the owner. You become a manager, and only they can '
          'transfer it back.',
      phrase: member.email,
      phraseHint: "the new owner's email",
      confirmLabel: 'Transfer',
    );
    if (!confirmed) return;

    await _run(
      (repo) => repo.transferOwnership(member.userId),
      '$tenantName now belongs to ${member.email}.',
      after: () {
        ref
          ..invalidate(membershipsProvider)
          ..invalidate(permissionsProvider);
        // The Danger row has just stopped being theirs — standing on a screen
        // that no longer belongs to you is not a state worth rendering.
        if (mounted) context.go(Routes.settings);
      },
    );
  }

  Future<void> _delete() async {
    final tenantName = ref.read(activeTenantProvider)?.name ?? '';
    final confirmed = await showConfirmPhraseDialog(
      context,
      title: 'Delete $tenantName?',
      message:
          'Everything — orders, bills, menu, tables, customers and stock — is '
          'permanently removed after a 7-day grace period. Cancel any time '
          'before then to keep it.',
      phrase: tenantName,
      phraseHint: 'the restaurant name',
      confirmLabel: 'Delete restaurant',
    );
    if (!confirmed) return;

    await _run(
      (repo) => repo.requestDeletion(),
      '$tenantName is scheduled for deletion.',
    );
  }

  Future<void> _cancelDeletion() async {
    // No phrase here: undoing danger is not dangerous, and making someone
    // retype a name to keep their restaurant is a guard pointed the wrong way.
    await _run(
      (repo) => repo.cancelDeletion(),
      'Deletion cancelled. Nothing will be removed.',
    );
  }

  Future<void> _run(
    Future<void> Function(DangerRepository repo) work,
    String success, {
    VoidCallback? after,
  }) async {
    final repo = _repo;
    if (repo == null || _busy) return;
    setState(() => _busy = true);
    String message;
    try {
      await work(repo);
      message = success;
      ref.invalidate(dangerDataProvider);
      after?.call();
    } on PosFailure catch (e) {
      message = e.message;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final tenant = ref.watch(activeTenantProvider);
    final data = ref.watch(dangerDataProvider);

    if (tenant != null && tenant.role != 'owner') {
      return const AppScaffold(
        title: 'Dangerous area',
        showDrawer: false,
        body: _OwnerOnly(),
      );
    }

    return AppScaffold(
      title: 'Dangerous area',
      subtitle: tenant?.name,
      showDrawer: false,
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _Problem(
          message: '$e',
          onRetry: () => ref.invalidate(dangerDataProvider),
        ),
        data: (value) {
          if (value == null) {
            return const Center(child: Text('No restaurant selected.'));
          }
          final scheduled = value.deletionScheduledAt;
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(dangerDataProvider),
            child: ListView(
              padding: const EdgeInsets.only(top: 6, bottom: 24),
              children: [
                Card(
                  margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                  child: ListTile(
                    leading: const Icon(Icons.storefront_outlined),
                    title: Text(tenant?.name ?? 'This restaurant'),
                    subtitle: Text(value.planLabel),
                  ),
                ),
                PlanUsageCard(usage: value.usage),
                if (scheduled != null)
                  _ScheduledBanner(
                    at: scheduled,
                    busy: _busy,
                    onCancel: _cancelDeletion,
                  ),
                _DangerRow(
                  icon: Icons.restart_alt,
                  title: 'Reset restaurant',
                  detail:
                      'Wipe menu, orders, customers or the lot — and keep the '
                      'restaurant itself.',
                  enabled: !_busy,
                  onTap: () => context.push(Routes.settingsDangerReset),
                ),
                _DangerRow(
                  icon: Icons.swap_horiz,
                  title: 'Transfer ownership',
                  detail: 'Hand the restaurant to someone already on the team.',
                  enabled: !_busy,
                  onTap: () => _transfer(value),
                ),
                if (scheduled == null)
                  _DangerRow(
                    icon: Icons.delete_forever_outlined,
                    title: 'Delete restaurant',
                    detail: 'Ends it, after seven days to change your mind.',
                    enabled: !_busy,
                    onTap: _delete,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ScheduledBanner extends StatelessWidget {
  const _ScheduledBanner({
    required this.at,
    required this.busy,
    required this.onCancel,
  });

  final DateTime at;
  final bool busy;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.warning_amber_outlined,
                  color: theme.colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Scheduled for deletion',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Everything is permanently removed on ${billDateTime(at)}. '
              'Cancelling before then keeps it all.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: busy ? null : onCancel,
              child: const Text('Cancel deletion'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DangerRow extends StatelessWidget {
  const _DangerRow({
    required this.icon,
    required this.title,
    required this.detail,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String detail;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: ListTile(
        minTileHeight: Tokens.tapTarget + 12,
        // The word in the title is what says this is dangerous; the tint only
        // agrees with it.
        leading: Icon(icon, color: theme.colorScheme.error),
        title: Text(title),
        subtitle: Text(detail),
        trailing: const Icon(Icons.chevron_right),
        enabled: enabled,
        onTap: onTap,
      ),
    );
  }
}

class _OwnerOnly extends StatelessWidget {
  const _OwnerOnly();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 36),
            const SizedBox(height: 12),
            Text(
              'Only the owner can open this.',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Resetting, transferring and deleting a restaurant are the '
              "owner's alone.",
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
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
              "Couldn't load this restaurant.",
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
