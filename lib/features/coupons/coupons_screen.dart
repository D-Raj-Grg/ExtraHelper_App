import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_scaffold.dart';
import '../../core/format/money.dart';
import '../../core/format/when.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/notice.dart';
import '../../data/supabase/coupons_repository.dart';
import '../../data/supabase/pos_repository.dart' show PosFailure;
import '../tenant/tenant_providers.dart';
import 'coupon_qr_sheet.dart';
import 'coupon_sheet.dart';
import 'coupon_status.dart';
import 'coupons_providers.dart';
import 'no_coupon_access.dart';

/// The flyer codes: what each is worth, whether it is running, how often it
/// was used. The web's Insights → Coupons, on the phone.
///
/// `coupons.view` opens the door; `coupons.manage` adds the levers (new,
/// edit, pause, delete). The QR is for everyone who can see the list — a
/// waiter showing a guest the code is the point of having it here.
class CouponsScreen extends ConsumerStatefulWidget {
  const CouponsScreen({super.key});

  @override
  ConsumerState<CouponsScreen> createState() => _CouponsScreenState();
}

class _CouponsScreenState extends ConsumerState<CouponsScreen> {
  bool _busy = false;

  void _refresh() => ref.invalidate(couponsProvider);

  Future<void> _reload() => ref.refresh(couponsProvider.future);

  void _say(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  CouponsRepository? get _repo {
    final tenant = ref.read(activeTenantProvider);
    if (tenant == null) return null;
    return ref.read(couponsRepositoryProvider(tenant.tenantId));
  }

  Future<void> _run(
    Future<void> Function(CouponsRepository) work,
    String done,
  ) async {
    final repo = _repo;
    if (repo == null || _busy) return;
    setState(() => _busy = true);
    try {
      await work(repo);
      _refresh();
      _say(done);
    } on PosFailure catch (e) {
      _say(e.message);
    } catch (_) {
      _say("Couldn't reach the coupon list.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create(String currency) async {
    final draft = await showCouponSheet(context, currency: currency);
    if (draft == null || !mounted) return;
    await _run((r) => r.save(draft), 'Coupon created.');
  }

  Future<void> _edit(Coupon c, String currency) async {
    final draft = await showCouponSheet(
      context,
      currency: currency,
      editing: c,
    );
    if (draft == null || !mounted) return;
    await _run((r) => r.save(draft), 'Coupon saved.');
  }

  Future<void> _toggle(Coupon c) => _run(
    (r) => r.setActive(c, !c.isActive),
    c.isActive ? 'Coupon paused.' : 'Coupon resumed.',
  );

  Future<void> _delete(Coupon c) async {
    final choice = await _confirmDelete(context, c);
    if (choice == null || !mounted) return;
    switch (choice) {
      case _DeleteChoice.delete:
        await _run((r) => r.delete(c.id), 'Coupon deleted.');
      case _DeleteChoice.pause:
        await _run((r) => r.setActive(c, false), 'Coupon paused.');
    }
  }

  Future<void> _actions(Coupon c, String currency, bool canManage) async {
    final action = await showModalBottomSheet<_Action>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  c.code,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(couponSummary(c, currency)),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.qr_code_2),
                title: const Text('Show QR'),
                onTap: () => Navigator.of(sheetContext).pop(_Action.qr),
              ),
              if (canManage) ...[
                ListTile(
                  leading: Icon(
                    c.isActive
                        ? Icons.pause_circle_outline
                        : Icons.play_circle_outline,
                  ),
                  title: Text(c.isActive ? 'Pause' : 'Resume'),
                  onTap: () => Navigator.of(sheetContext).pop(_Action.toggle),
                ),
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Edit'),
                  onTap: () => Navigator.of(sheetContext).pop(_Action.edit),
                ),
                ListTile(
                  leading: Icon(
                    Icons.delete_outline,
                    color: Theme.of(sheetContext).colorScheme.error,
                  ),
                  title: Text(
                    'Delete',
                    style: TextStyle(
                      color: Theme.of(sheetContext).colorScheme.error,
                    ),
                  ),
                  onTap: () => Navigator.of(sheetContext).pop(_Action.delete),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case _Action.qr:
        await showCouponQrSheet(context, coupon: c, currency: currency);
      case _Action.toggle:
        await _toggle(c);
      case _Action.edit:
        await _edit(c, currency);
      case _Action.delete:
        await _delete(c);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(identityStatusProvider);
    final canView = ref.watch(hasPermissionProvider('coupons.view'));
    final canManage = ref.watch(hasPermissionProvider('coupons.manage'));
    final currency = ref.watch(activeTenantProvider)?.currency ?? 'USD';
    final ready = status == IdentityStatus.ready && canView;

    return AppScaffold(
      title: 'Coupons',
      floatingActionButton: ready && canManage
          ? FloatingActionButton.extended(
              onPressed: _busy ? null : () => _create(currency),
              icon: const Icon(Icons.add),
              label: const Text('New coupon'),
            )
          : null,
      body: switch (status) {
        IdentityStatus.unavailable => Padding(
          padding: const EdgeInsets.all(16),
          child: RetryNotice(
            message: "Couldn't check your access.",
            detail: '${ref.watch(identityErrorProvider)}',
            onRetry: () => ref
              ..invalidate(membershipsProvider)
              ..invalidate(permissionsProvider),
          ),
        ),
        IdentityStatus.ready when !canView => const NoCouponAccess(),
        IdentityStatus.ready => _Body(
          currency: currency,
          canManage: canManage,
          onRetry: _refresh,
          onRefresh: _reload,
          onTap: (c) => _actions(c, currency, canManage),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

enum _Action { qr, toggle, edit, delete }

enum _DeleteChoice { delete, pause }

/// A used coupon cannot go (the server refuses: the bills reference it), so
/// the dialog says so up front and offers the pause instead.
Future<_DeleteChoice?> _confirmDelete(BuildContext context, Coupon c) =>
    showDialog<_DeleteChoice>(
      context: context,
      builder: (dialogContext) {
        final scheme = Theme.of(dialogContext).colorScheme;
        final used = c.redemptions > 0;
        return AlertDialog(
          title: Text('Delete ${c.code}?'),
          content: Text(
            used
                ? 'This coupon is on ${c.redemptions} '
                      '${c.redemptions == 1 ? 'bill' : 'bills'}, so it '
                      'cannot be deleted. Pause it instead — nobody can use '
                      'it, and the past bills keep their discount.'
                : 'Nobody has used it yet. This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            if (used)
              FilledButton(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(_DeleteChoice.pause),
                child: const Text('Pause instead'),
              )
            else
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                ),
                onPressed: () =>
                    Navigator.of(dialogContext).pop(_DeleteChoice.delete),
                child: const Text('Delete coupon'),
              ),
          ],
        );
      },
    );

class _Body extends ConsumerWidget {
  const _Body({
    required this.currency,
    required this.canManage,
    required this.onRetry,
    required this.onRefresh,
    required this.onTap,
  });

  final String currency;
  final bool canManage;
  final VoidCallback onRetry;
  final Future<void> Function() onRefresh;
  final ValueChanged<Coupon> onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coupons = ref.watch(couponsProvider);
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
        children: coupons.when(
          loading: () => const [
            Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
          error: (e, _) => [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: RetryNotice(
                message: "Couldn't load coupons.",
                detail: '$e',
                icon: Icons.cloud_off_outlined,
                onRetry: onRetry,
              ),
            ),
          ],
          data: (list) => [
            if (list.isEmpty)
              _Empty(canManage: canManage)
            else
              for (final c in list)
                _CouponTile(
                  key: ValueKey(c.id),
                  coupon: c,
                  currency: currency,
                  onTap: () => onTap(c),
                ),
          ],
        ),
      ),
    );
  }
}

class _CouponTile extends StatelessWidget {
  const _CouponTile({
    super.key,
    required this.coupon,
    required this.currency,
    required this.onTap,
  });

  final Coupon coupon;
  final String currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = coupon;
    final muted = theme.colorScheme.onSurfaceVariant;
    final status = couponStatus(c, DateTime.now());
    final limit = c.usageLimit;
    final uses = limit == null ? '${c.usedCount}' : '${c.usedCount} / $limit';
    final validity = switch ((c.validFrom, c.validTo)) {
      (null, null) => 'Any time',
      (final f?, null) => 'From ${billDate(f)}',
      (null, final t?) => 'Through ${billDate(lastDayOf(t))}',
      (final f?, final t?) => '${billDate(f)} – ${billDate(lastDayOf(t))}',
    };
    const tabular = [FontFeature.tabularFigures()];

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
        isThreeLine: true,
        title: Row(
          children: [
            Expanded(
              child: Text(
                c.code,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            _StatusBadge(status: status),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (c.name != null)
              Text(
                c.name!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            Text(
              couponSummary(c, currency),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
            const SizedBox(height: 2),
            Text(
              '$validity · Used $uses'
              '${c.redemptions > 0 ? ' · Given ${money(c.discountGivenCents, currency)}' : ''}',
              maxLines: 2,
              style: theme.textTheme.bodySmall?.copyWith(
                color: muted,
                fontFeatures: tabular,
              ),
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final CouponStatus status;

  @override
  Widget build(BuildContext context) {
    // Icon + word carry the state; the semantic hue only reinforces.
    final semantic = context.semantic;
    final (icon, color) = switch (status) {
      CouponStatus.active => (Icons.check_circle_outline, semantic.goodText),
      CouponStatus.paused => (Icons.pause_circle_outline, semantic.neutral),
      CouponStatus.scheduled => (Icons.schedule, semantic.infoText),
      CouponStatus.expired => (Icons.event_busy, semantic.dangerText),
      CouponStatus.usedUp => (Icons.block, semantic.dangerText),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(
          couponStatusLabel(status),
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: color),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.canManage});

  final bool canManage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Column(
        children: [
          const Icon(Icons.confirmation_number_outlined, size: 36),
          const SizedBox(height: 12),
          Text('No coupons yet', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            canManage
                ? 'Make one with New coupon: a code for the flyer, what it '
                      'takes off, and when it runs. Its QR is ready to show '
                      'or share the moment it is saved.'
                : 'An owner or manager creates coupons. Once there is one, '
                      'its QR shows here for guests to scan.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
