import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_scaffold.dart';
import '../../core/theme/tokens.dart';
import '../../data/supabase/danger_repository.dart';
import '../../data/supabase/pos_repository.dart' show PosFailure;
import '../../data/sync/sync_providers.dart';
import '../pos/bill_providers.dart';
import '../pos/pos_providers.dart';
import '../tenant/tenant_providers.dart';
import 'confirm_phrase_dialog.dart';
import 'danger_domains.dart';
import 'settings_providers.dart';

/// Pick what to wipe, then retype the restaurant's name.
///
/// A screen rather than a dialog: eleven choices plus an "everything" switch is
/// more than a phone-sized dialog can hold without scrolling inside a scroll.
class DangerResetScreen extends ConsumerStatefulWidget {
  const DangerResetScreen({super.key});

  @override
  ConsumerState<DangerResetScreen> createState() => _DangerResetScreenState();
}

class _DangerResetScreenState extends ConsumerState<DangerResetScreen> {
  final _selected = <String>{};
  bool _everything = false;
  bool _busy = false;

  bool get _armed => _busy ? false : _everything || _selected.isNotEmpty;

  Future<void> _reset() async {
    final tenant = ref.read(activeTenantProvider);
    if (tenant == null || !_armed) return;

    final domains = _everything
        ? const [resetEverything]
        : _selected.toList(growable: false);
    final what = _everything
        ? 'Everything in ${tenant.name}'
        : '${domains.length} ${domains.length == 1 ? 'area' : 'areas'} of '
              '${tenant.name}';

    final confirmed = await showConfirmPhraseDialog(
      context,
      title: 'Reset ${tenant.name}?',
      message: '$what will be wiped. This cannot be undone, and the '
          'restaurant itself stays where it is.',
      phrase: tenant.name,
      phraseHint: 'the restaurant name',
      confirmLabel: 'Reset now',
    );
    if (!confirmed) return;

    setState(() => _busy = true);
    String message;
    var done = false;
    try {
      await ref
          .read(dangerRepositoryProvider(tenant.tenantId))
          .resetTenant(domains);
      done = true;
      message = 'Reset done.';
    } on PosFailure catch (e) {
      message = e.message;
    } finally {
      if (mounted) setState(() => _busy = false);
    }

    if (done) {
      // The local copy now describes rows that no longer exist. Left alone,
      // the cache serves a deleted menu and the outbox retries writes against
      // ids the server has forgotten — forever, into dead.
      await ref.read(posCacheProvider).wipe();
      final outbox = ref.read(outboxStoreProvider);
      for (final entry in await outbox.all()) {
        await outbox.discard(entry.id);
      }
      ref
        ..invalidate(outboxStatusProvider)
        ..invalidate(membershipsProvider)
        ..invalidate(permissionsProvider)
        ..invalidate(tenantSettingsProvider)
        ..invalidate(branchesProvider)
        ..invalidate(printerRegistryProvider)
        ..invalidate(dangerDataProvider)
        ..invalidate(menuProvider)
        ..invalidate(filteredBillsProvider)
        ..invalidate(completedOrdersProvider);
      if (mounted) {
        setState(() {
          _selected.clear();
          _everything = false;
        });
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tenant = ref.watch(activeTenantProvider);

    return AppScaffold(
      title: 'Reset restaurant',
      subtitle: tenant?.name,
      showDrawer: false,
      bottomNavigationBar: Material(
        elevation: 3,
        color: theme.colorScheme.surface,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _everything
                      ? 'Everything selected'
                      : '${_selected.length} of ${resetDomains.length} selected',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: Tokens.tapTarget + 4,
                  child: FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      foregroundColor: theme.colorScheme.onErrorContainer,
                      backgroundColor: theme.colorScheme.errorContainer,
                    ),
                    onPressed: _armed ? _reset : null,
                    child: Text(_busy ? 'Resetting…' : 'Reset it!'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          Text(
            'Everything you pick is wiped for good. The restaurant, your team '
            'and your plan stay as they are.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          for (final domain in resetDomains)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _everything || _selected.contains(domain.key),
              // Disabled under "everything" rather than hidden: the list still
              // says what is about to go, which is the point of reading it.
              onChanged: _everything || _busy
                  ? null
                  : (checked) => setState(() {
                      if (checked ?? false) {
                        _selected.add(domain.key);
                      } else {
                        _selected.remove(domain.key);
                      }
                    }),
              title: Text(domain.label),
              subtitle: Text(domain.detail),
            ),
          const Divider(height: 24),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _everything,
            onChanged: _busy
                ? null
                : (checked) => setState(() => _everything = checked ?? false),
            title: Text(
              'Reset everything',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: const Text(
              'Every area above, in one go — the restaurant back to its first '
              'day.',
            ),
          ),
        ],
      ),
    );
  }
}
