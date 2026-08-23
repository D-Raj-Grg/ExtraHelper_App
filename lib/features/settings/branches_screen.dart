import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_scaffold.dart';
import '../../data/supabase/branches_repository.dart';
import '../../data/supabase/pos_repository.dart' show PosFailure;
import '../tenant/tenant_providers.dart';
import 'branch_sheet.dart';
import 'settings_providers.dart';

/// Where this restaurant trades.
///
/// Gated on manager rather than on `settings.edit`: `branches_manage` is a
/// role policy, not a permission one, so a custom role holding `settings.edit`
/// without being a manager would be offered controls RLS then refuses.
class BranchesScreen extends ConsumerStatefulWidget {
  const BranchesScreen({super.key});

  @override
  ConsumerState<BranchesScreen> createState() => _BranchesScreenState();
}

class _BranchesScreenState extends ConsumerState<BranchesScreen> {
  bool _busy = false;

  BranchesRepository? get _repo {
    final tenant = ref.read(activeTenantProvider);
    if (tenant == null) return null;
    return ref.read(branchesRepositoryProvider(tenant.tenantId));
  }

  Future<void> _run(Future<void> Function(BranchesRepository repo) work,
      String success) async {
    final repo = _repo;
    if (repo == null || _busy) return;
    setState(() => _busy = true);
    String message;
    try {
      await work(repo);
      message = success;
      ref.invalidate(branchesProvider);
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

  Future<void> _add() async {
    final draft = await showBranchSheet(context);
    if (draft == null) return;
    await _run(
      (repo) => repo.create(name: draft.name, address: draft.address),
      'Branch added.',
    );
  }

  Future<void> _edit(Branch branch) async {
    final draft = await showBranchSheet(context, editing: branch);
    if (draft == null) return;
    await _run(
      (repo) => repo.update(
        id: branch.id,
        name: draft.name,
        address: draft.address,
      ),
      'Branch saved.',
    );
  }

  Future<void> _delete(Branch branch) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${branch.name}?'),
        content: const Text(
          'Printers and orders pointing at this branch lose their location. '
          "Anything already printed doesn't change.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run((repo) => repo.remove(branch), 'Branch deleted.');
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = ref.watch(isManagerProvider);
    final branches = ref.watch(branchesProvider);

    return AppScaffold(
      title: 'Branches',
      showDrawer: false,
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: _busy ? null : _add,
              icon: const Icon(Icons.add),
              label: const Text('Add branch'),
            )
          : null,
      body: branches.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _Problem(
          message: '$e',
          onRetry: () => ref.invalidate(branchesProvider),
        ),
        data: (rows) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(branchesProvider),
          child: rows.isEmpty
              ? const _Empty()
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                  itemCount: rows.length,
                  itemBuilder: (context, index) => _BranchCard(
                    branch: rows[index],
                    canEdit: canEdit,
                    busy: _busy,
                    onEdit: () => _edit(rows[index]),
                    onDelete: () => _delete(rows[index]),
                  ),
                ),
        ),
      ),
    );
  }
}

class _BranchCard extends StatelessWidget {
  const _BranchCard({
    required this.branch,
    required this.canEdit,
    required this.busy,
    required this.onEdit,
    required this.onDelete,
  });

  final Branch branch;
  final bool canEdit;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          branch.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (branch.isDefault) ...[
                        const SizedBox(width: 8),
                        // A word, not a colour: everything without a branch of
                        // its own belongs to this one, and that is worth
                        // reading rather than decoding.
                        Chip(
                          label: const Text('Default'),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          labelStyle: theme.textTheme.labelSmall,
                        ),
                      ],
                    ],
                  ),
                  if (branch.address != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        branch.address!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // The default branch is deliberately unarmed: it anchors every
            // order, printer and station that names no branch of its own.
            if (canEdit && !branch.isDefault) ...[
              IconButton(
                tooltip: 'Edit',
                icon: const Icon(Icons.edit_outlined),
                onPressed: busy ? null : onEdit,
              ),
              IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline),
                onPressed: busy ? null : onDelete,
              ),
            ],
            if (canEdit && branch.isDefault)
              IconButton(
                tooltip: 'Edit',
                icon: const Icon(Icons.edit_outlined),
                onPressed: busy ? null : onEdit,
              ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 80),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Icon(Icons.location_off_outlined, size: 36),
                const SizedBox(height: 12),
                Text(
                  'No branches yet.',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  'Add one for each place this restaurant trades, and printers '
                  'can be pointed at the right counter.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ],
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
              "Couldn't load your branches.",
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
