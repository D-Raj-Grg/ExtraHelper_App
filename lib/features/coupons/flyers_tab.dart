import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/when.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/notice.dart';
import '../../data/supabase/coupon_batches_repository.dart';
import '../../data/supabase/pos_repository.dart' show PosFailure;
import '../tenant/tenant_providers.dart';
import 'coupon_status.dart';
import 'coupons_providers.dart';
import 'flyer_design_screen.dart';
import 'flyer_export.dart';
import 'run_codes_sheet.dart';
import 'run_sheet.dart';

/// Make a run from a draft the sheet returned. Shared by the screen's button
/// and the empty state so the busy/refresh/snackbar story lives in one place.
Future<void> createFlyerRun(
  BuildContext context,
  WidgetRef ref, {
  required String currency,
  required void Function(String) say,
}) async {
  final draft = await showNewRunSheet(context, currency: currency);
  if (draft == null || !context.mounted) return;
  final tenant = ref.read(activeTenantProvider);
  if (tenant == null) return;
  try {
    final id = await ref
        .read(couponBatchesRepositoryProvider(tenant.tenantId))
        .create(draft);
    ref.invalidate(couponStatsProvider);
    say('${draft.count} codes made.');
    // Step 2 of the wizard: put the code and QR on a picture.
    final runs = await ref.refresh(couponBatchesProvider.future);
    final made = runs.where((b) => b.id == id).firstOrNull;
    if (made != null && context.mounted) {
      await showFlyerDesignScreen(context, batch: made);
      ref.invalidate(couponBatchesProvider);
    }
  } on PosFailure catch (e) {
    say(e.message);
  } catch (_) {
    say("Couldn't reach the flyers.");
  }
}

/// The web's Coupons → Flyers tab: every print run with how many of its codes
/// are out, used and still live. Tap a run for its codes, the QR of each and
/// the pause / edit levers. Designing and printing the flyer stays on the web.
class FlyersTab extends ConsumerStatefulWidget {
  const FlyersTab({
    super.key,
    required this.currency,
    required this.canManage,
    required this.say,
  });

  final String currency;
  final bool canManage;
  final void Function(String) say;

  @override
  ConsumerState<FlyersTab> createState() => _FlyersTabState();
}

class _FlyersTabState extends ConsumerState<FlyersTab> {
  bool _busy = false;

  CouponBatchesRepository? get _repo {
    final tenant = ref.read(activeTenantProvider);
    if (tenant == null) return null;
    return ref.read(couponBatchesRepositoryProvider(tenant.tenantId));
  }

  Future<void> _run(
    Future<void> Function(CouponBatchesRepository) work,
    String done,
  ) async {
    final repo = _repo;
    if (repo == null || _busy) return;
    setState(() => _busy = true);
    try {
      await work(repo);
      ref
        ..invalidate(couponBatchesProvider)
        ..invalidate(couponStatsProvider);
      widget.say(done);
    } on PosFailure catch (e) {
      widget.say(e.message);
    } catch (_) {
      widget.say("Couldn't reach the flyers.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _actions(CouponBatch b) async {
    final action = await showModalBottomSheet<_RunAction>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  b.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  couponValueLabel(b.type, b.value, widget.currency),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.list_alt_outlined),
                title: const Text('Codes'),
                onTap: () => Navigator.of(sheetContext).pop(_RunAction.codes),
              ),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf_outlined),
                title: Text('Download all ${b.issued} flyers (PDF)'),
                subtitle: b.designId == null
                    ? const Text('Add a design first.')
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(_RunAction.pdfAll),
              ),
              ListTile(
                leading: const Icon(Icons.fact_check_outlined),
                title: const Text('Proof (1 page)'),
                subtitle: const Text(
                  'Print one and scan it before printing the whole run.',
                ),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_RunAction.pdfProof),
              ),
              if (widget.canManage) ...[
                ListTile(
                  leading: const Icon(Icons.palette_outlined),
                  title: Text(
                    b.designId == null ? 'Add a design' : 'Change design',
                  ),
                  onTap: () =>
                      Navigator.of(sheetContext).pop(_RunAction.design),
                ),
                ListTile(
                  leading: Icon(
                    b.isPaused
                        ? Icons.play_circle_outline
                        : Icons.pause_circle_outline,
                  ),
                  title: Text(b.isPaused ? 'Resume run' : 'Pause run'),
                  subtitle: Text(
                    b.isPaused
                        ? 'Every code in the run works again.'
                        : 'Stops every code, e.g. when flyers go missing.',
                  ),
                  onTap: () =>
                      Navigator.of(sheetContext).pop(_RunAction.toggle),
                ),
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Edit name & dates'),
                  onTap: () => Navigator.of(sheetContext).pop(_RunAction.edit),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case _RunAction.codes:
        await showRunCodesSheet(
          context,
          batch: b,
          currency: widget.currency,
          canManage: widget.canManage,
        );
        ref.invalidate(couponBatchesProvider);
      case _RunAction.design:
        await showFlyerDesignScreen(context, batch: b);
        ref.invalidate(couponBatchesProvider);
      case _RunAction.pdfAll:
        await exportFlyers(context, ref, batch: b, say: widget.say);
      case _RunAction.pdfProof:
        await exportFlyers(
          context,
          ref,
          batch: b,
          proof: true,
          say: widget.say,
        );
      case _RunAction.toggle:
        await _run(
          (r) => r.setActive(b.id, b.isPaused),
          b.isPaused ? 'Run resumed.' : 'Run paused.',
        );
      case _RunAction.edit:
        final edit = await showEditRunSheet(context, batch: b);
        if (edit == null || !mounted) return;
        await _run((r) => r.update(b.id, edit), 'Run saved.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final batches = ref.watch(couponBatchesProvider);
    return RefreshIndicator(
      onRefresh: () => ref.refresh(couponBatchesProvider.future),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
        children: batches.when(
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
                message: "Couldn't load the flyers.",
                detail: '$e',
                icon: Icons.cloud_off_outlined,
                onRetry: () => ref.invalidate(couponBatchesProvider),
              ),
            ),
          ],
          data: (list) => [
            if (list.isEmpty)
              _EmptyRuns(canManage: widget.canManage)
            else
              for (final b in list)
                _RunTile(
                  key: ValueKey(b.id),
                  batch: b,
                  currency: widget.currency,
                  onTap: () => _actions(b),
                ),
          ],
        ),
      ),
    );
  }
}

enum _RunAction { codes, design, pdfAll, pdfProof, toggle, edit }

class _RunTile extends StatelessWidget {
  const _RunTile({
    super.key,
    required this.batch,
    required this.currency,
    required this.onTap,
  });

  final CouponBatch batch;
  final String currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = batch;
    final muted = theme.colorScheme.onSurfaceVariant;
    final validity = switch ((b.validFrom, b.validTo)) {
      (null, null) => 'Any time',
      (final f?, null) => 'From ${billDate(f)}',
      (null, final t?) => 'Through ${billDate(lastDayOf(t))}',
      (final f?, final t?) => '${billDate(f)} – ${billDate(lastDayOf(t))}',
    };
    const tabular = [FontFeature.tabularFigures()];
    final semantic = context.semantic;
    final (icon, color, word) = b.isPaused
        ? (Icons.pause_circle_outline, semantic.neutral, 'Paused')
        : (Icons.check_circle_outline, semantic.goodText, 'Running');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
        isThreeLine: true,
        title: Row(
          children: [
            Expanded(
              child: Text(
                b.name,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(
              word,
              style: theme.textTheme.labelMedium?.copyWith(color: color),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${couponValueLabel(b.type, b.value, currency)} · $validity',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
            const SizedBox(height: 2),
            Text(
              '${b.issued} made · ${b.shared} handed out · '
              '${b.redeemed} used · ${b.unused} free',
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

class _EmptyRuns extends StatelessWidget {
  const _EmptyRuns({required this.canManage});

  final bool canManage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Column(
        children: [
          const Icon(Icons.local_print_shop_outlined, size: 36),
          const SizedBox(height: 12),
          Text('No flyer runs yet', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            canManage
                ? 'A run is a stack of single-use codes, one per flyer. Make '
                      'one with New run; design and print the flyers on the web.'
                : 'An owner or manager makes flyer runs. Once there is one, '
                      'its codes show here.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
