import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_scaffold.dart';
import '../../data/supabase/expenses_repository.dart';
import '../../data/supabase/pos_repository.dart' show PosFailure;
import '../tenant/tenant_providers.dart';
import 'expenses_providers.dart';

/// Add, rename and retire expense categories (`expenses.manage`; the RPCs
/// refuse anyone else). Retired, not deleted: past entries keep their label.
class ExpenseCategoriesScreen extends ConsumerStatefulWidget {
  const ExpenseCategoriesScreen({super.key});

  @override
  ConsumerState<ExpenseCategoriesScreen> createState() =>
      _ExpenseCategoriesScreenState();
}

class _ExpenseCategoriesScreenState
    extends ConsumerState<ExpenseCategoriesScreen> {
  bool _busy = false;

  Future<void> _run(
    Future<void> Function(ExpensesRepository repo) work,
    String success,
  ) async {
    final tenant = ref.read(activeTenantProvider);
    if (tenant == null || _busy) return;
    setState(() => _busy = true);
    String message;
    try {
      await work(ref.read(expensesRepositoryProvider(tenant.tenantId)));
      message = success;
      ref.invalidate(expenseCategoriesProvider);
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

  Future<void> _name({ExpenseCategory? editing}) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(initial: editing?.name ?? ''),
    );
    if (name == null) return;
    await _run(
      (repo) => repo.saveCategory(id: editing?.id, name: name),
      editing == null ? 'Category added.' : 'Renamed.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final cats = ref.watch(expenseCategoriesProvider);
    return AppScaffold(
      title: 'Expense categories',
      showDrawer: false,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : () => _name(),
        icon: const Icon(Icons.add),
        label: const Text('Add category'),
      ),
      body: cats.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (rows) {
          final active = rows.where((c) => !c.archived).toList();
          final retired = rows.where((c) => c.archived).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
            children: [
              for (final c in active)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(c.name),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Rename ${c.name}',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: _busy ? null : () => _name(editing: c),
                        ),
                        IconButton(
                          tooltip: 'Retire ${c.name}',
                          icon: const Icon(Icons.archive_outlined),
                          onPressed: _busy
                              ? null
                              : () => _run(
                                  (repo) => repo.archiveCategory(c.id),
                                  'Retired ${c.name}.',
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (retired.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                  child: Text(
                    'Retired',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                for (final c in retired)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(c.name),
                      trailing: TextButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _run(
                                (repo) =>
                                    repo.saveCategory(id: c.id, name: c.name),
                                'Restored ${c.name}.',
                              ),
                        icon: const Icon(Icons.undo),
                        label: const Text('Restore'),
                      ),
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.initial});

  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial.isEmpty ? 'New category' : 'Rename category'),
      content: TextField(
        controller: _name,
        autofocus: true,
        maxLength: 60,
        decoration: const InputDecoration(
          labelText: 'Name',
          hintText: 'Cooking oil',
          border: OutlineInputBorder(),
        ),
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _name.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(_name.text.trim()),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
