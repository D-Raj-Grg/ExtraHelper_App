import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_scaffold.dart';
import '../../core/format/labels.dart';
import '../../core/layout/breakpoints.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/notice.dart';
import '../../core/widgets/table_glyph.dart';
import '../../data/supabase/pos_repository.dart' show PosFailure;
import '../../data/supabase/tables_admin_repository.dart';
import '../pos/models.dart';
import '../pos/order_composer.dart' show tableStateColor;
import '../pos/pos_providers.dart';
import '../tenant/tenant_providers.dart';
import 'add_floor_sheet.dart';
import 'add_table_sheet.dart';
import 'no_tables_access.dart';
import 'table_qr_sheet.dart';

/// Floors and tables, the admin view: add, remove, and print the QR for each.
///
/// `tables.view` opens the door; `tables.edit` (or a manager) adds the
/// levers. The server checks both again.
class TablesAdminScreen extends ConsumerStatefulWidget {
  const TablesAdminScreen({super.key});

  @override
  ConsumerState<TablesAdminScreen> createState() => _TablesAdminScreenState();
}

class _TablesAdminScreenState extends ConsumerState<TablesAdminScreen> {
  bool _busy = false;

  void _say(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  TablesAdminRepository? get _repo {
    final tenant = ref.read(activeTenantProvider);
    if (tenant == null) return null;
    return ref.read(tablesAdminRepositoryProvider(tenant.tenantId));
  }

  /// Realtime only merges *changed* rows, so an insert or delete would not
  /// show — pull both lists again. Unawaited: a slow read must not hold the
  /// tap's spinner.
  void _refreshLists() {
    unawaited(ref.read(floorsProvider.notifier).refresh());
    unawaited(ref.read(tablesProvider.notifier).refresh());
  }

  Future<void> _reload() async {
    await ref.read(floorsProvider.notifier).refresh();
    await ref.read(tablesProvider.notifier).refresh();
  }

  Future<void> _run(
    Future<void> Function(TablesAdminRepository) work,
    String done,
  ) async {
    final repo = _repo;
    if (repo == null || _busy) return;
    setState(() => _busy = true);
    try {
      await work(repo);
      _refreshLists();
      _say(done);
    } on PosFailure catch (e) {
      _say(e.message);
    } catch (e) {
      _say(e.toString().isEmpty ? "Couldn't save that." : "Couldn't save: $e");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addFloor() async {
    final name = await showAddFloorSheet(context);
    if (name == null || !mounted) return;
    await _run((r) => r.createFloor(name), 'Floor added.');
  }

  Future<void> _addTable(List<PosFloor> floors) async {
    final draft = await showAddTableSheet(context, floors: floors);
    if (draft == null || !mounted) return;
    await _run(
      (r) => r.createTable(
        label: draft.label,
        capacity: draft.capacity,
        floorId: draft.floorId,
      ),
      'Table ${draft.label} added.',
    );
  }

  Future<void> _delete(PosTable t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final scheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          title: Text('Delete table ${t.label}?'),
          content: const Text(
            'The QR printed for this table will stop working for good, even '
            'if you add a table with the same name. A table with an open '
            'order cannot be deleted.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete table'),
            ),
          ],
        );
      },
    );
    if (ok != true || !mounted) return;
    await _run((r) => r.deleteTable(t.id), 'Table ${t.label} deleted.');
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(identityStatusProvider);
    final canView = ref.watch(hasPermissionProvider('tables.view'));
    final canEdit =
        ref.watch(hasPermissionProvider('tables.edit')) ||
        ref.watch(isManagerProvider);
    final ready = status == IdentityStatus.ready && canView;
    final floors = ref.watch(floorsProvider).valueOrNull ?? const [];

    return AppScaffold(
      title: 'Floors & tables',
      maxBodyWidth: Breakpoints.wide,
      floatingActionButton: ready && canEdit
          ? FloatingActionButton.extended(
              onPressed: _busy ? null : () => _addTable(floors),
              icon: const Icon(Icons.add),
              label: const Text('Add table'),
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
        IdentityStatus.ready when !canView => const NoTablesAccess(),
        IdentityStatus.ready => _Body(
          canEdit: canEdit,
          onAddFloor: canEdit && !_busy ? _addFloor : null,
          onRefresh: _reload,
          onRetry: () => ref
            ..invalidate(tablesProvider)
            ..invalidate(floorsProvider),
          onQr: (t) => showTableQrSheet(context, table: t),
          onDelete: _delete,
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.canEdit,
    required this.onAddFloor,
    required this.onRefresh,
    required this.onRetry,
    required this.onQr,
    required this.onDelete,
  });

  final bool canEdit;
  final VoidCallback? onAddFloor;
  final Future<void> Function() onRefresh;
  final VoidCallback onRetry;
  final void Function(PosTable) onQr;
  final void Function(PosTable) onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tables = ref.watch(tablesProvider);
    final floors = ref.watch(floorsProvider).valueOrNull ?? const <PosFloor>[];

    return tables.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: RetryNotice(
          message: "Couldn't load the tables.",
          detail: '$e',
          onRetry: onRetry,
        ),
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return RefreshIndicator(
            onRefresh: onRefresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(32),
              children: [
                const SizedBox(height: 48),
                Icon(
                  Icons.table_restaurant_outlined,
                  size: 40,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 12),
                Text(
                  'No tables yet',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  canEdit
                      ? 'Add your first table, then print its QR so guests '
                            'can order from their seat.'
                      : 'An owner or manager can add tables here.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (floors.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Floors: ${floors.map((f) => f.name).join(', ')}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (onAddFloor != null) ...[
                  const SizedBox(height: 16),
                  Center(
                    child: FilledButton.tonalIcon(
                      onPressed: onAddFloor,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, Tokens.tapTarget),
                      ),
                      icon: const Icon(Icons.layers_outlined),
                      label: const Text('Add floor'),
                    ),
                  ),
                ],
              ],
            ),
          );
        }

        final groups = <({String name, List<PosTable> tables})>[];
        for (final f in floors) {
          final mine = rows.where((t) => t.floorId == f.id).toList();
          groups.add((name: f.name, tables: mine));
        }
        final known = floors.map((f) => f.id).toSet();
        final loose = rows
            .where((t) => t.floorId == null || !known.contains(t.floorId))
            .toList();
        if (loose.isNotEmpty) groups.add((name: 'No floor', tables: loose));

        return RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              12,
              8,
              12,
              96 + MediaQuery.viewPaddingOf(context).bottom,
            ),
            children: [
              if (onAddFloor != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonalIcon(
                    onPressed: onAddFloor,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, Tokens.tapTarget),
                    ),
                    icon: const Icon(Icons.layers_outlined),
                    label: const Text('Add floor'),
                  ),
                ),
              for (final g in groups) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
                  child: Text(
                    g.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (g.tables.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                    child: Text(
                      'No tables on this floor yet.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 190,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    // Grows with the OS text size so the card never clips.
                    mainAxisExtent:
                        140 *
                        MediaQuery.textScalerOf(
                          context,
                        ).scale(1).clamp(1.0, 1.8),
                  ),
                  itemCount: g.tables.length,
                  itemBuilder: (_, i) {
                    final t = g.tables[i];
                    return _TableAdminCard(
                      key: ValueKey(t.id),
                      table: t,
                      canEdit: canEdit,
                      onQr: () => onQr(t),
                      onDelete: () => onDelete(t),
                    );
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _TableAdminCard extends StatelessWidget {
  const _TableAdminCard({
    super.key,
    required this.table,
    required this.canEdit,
    required this.onQr,
    required this.onDelete,
  });

  final PosTable table;
  final bool canEdit;
  final VoidCallback onQr;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = tableStateColor(context, table.state);
    final stateLabel = tableStateLabel(table.state);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.radiusLg),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onQr,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 4, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Row(
                  children: [
                    TableGlyph(
                      seats: table.capacity,
                      filled: !table.isFree,
                      size: 44,
                      color: color,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            table.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '${table.capacity} seats',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Semantics(
                label: 'Status: $stateLabel',
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    stateLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    onPressed: onQr,
                    tooltip: 'QR',
                    constraints: const BoxConstraints.tightFor(
                      width: Tokens.tapTarget,
                      height: Tokens.tapTarget,
                    ),
                    color: theme.colorScheme.onSurface,
                    icon: const Icon(Icons.qr_code_2),
                  ),
                  if (canEdit)
                    IconButton(
                      onPressed: onDelete,
                      tooltip: 'Delete',
                      constraints: const BoxConstraints.tightFor(
                        width: Tokens.tapTarget,
                        height: Tokens.tapTarget,
                      ),
                      color: theme.colorScheme.error,
                      icon: const Icon(Icons.delete_outline),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
