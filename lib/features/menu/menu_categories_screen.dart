import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_scaffold.dart';
import '../../data/supabase/menu_repository.dart';
import '../../data/supabase/pos_repository.dart' show PosFailure;
import '../pos/pos_providers.dart' show menuProvider;
import '../tenant/tenant_providers.dart';
import 'item_edit_screen.dart' show showMenuNameDialog;
import 'menu_providers.dart';

/// Add, rename, and hide or show menu categories (`menu.edit`; the table
/// policies refuse anyone else). Hiding keeps the dishes but takes the section
/// off ordering screens, the same switch the web editor has.
class MenuCategoriesScreen extends ConsumerStatefulWidget {
  const MenuCategoriesScreen({super.key});

  @override
  ConsumerState<MenuCategoriesScreen> createState() =>
      _MenuCategoriesScreenState();
}

class _MenuCategoriesScreenState extends ConsumerState<MenuCategoriesScreen> {
  bool _busy = false;

  Future<void> _run(
    Future<void> Function(MenuRepository repo) work,
    String done,
  ) async {
    final tenant = ref.read(activeTenantProvider);
    if (tenant == null || _busy) return;
    setState(() => _busy = true);
    String message;
    try {
      await work(ref.read(menuRepositoryProvider(tenant.tenantId)));
      message = done;
      ref.invalidate(menuCategoriesProvider);
      ref.invalidate(menuEditItemsProvider);
      ref.invalidate(menuProvider);
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
    final name = await showMenuNameDialog(context, title: 'New category');
    if (name == null) return;
    await _run((r) => r.createCategory(name), '$name added.');
  }

  Future<void> _rename(MenuEditCategory c) async {
    final name = await showMenuNameDialog(
      context,
      title: 'Rename category',
      initial: c.name,
    );
    if (name == null || name == c.name) return;
    await _run((r) => r.updateCategory(c.id, name: name), 'Renamed.');
  }

  @override
  Widget build(BuildContext context) {
    final cats = ref.watch(menuCategoriesProvider);
    final items = ref.watch(menuEditItemsProvider).valueOrNull ?? const [];
    final canEdit = ref.watch(canEditMenuProvider);

    return AppScaffold(
      title: 'Menu categories',
      showDrawer: false,
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: _busy ? null : _add,
              icon: const Icon(Icons.add),
              label: const Text('Add category'),
            )
          : null,
      body: cats.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (rows) => rows.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'No categories yet. Add Starters, Mains, Drinks — '
                    'whatever sections your menu has.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                children: [
                  for (final c in rows)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        minTileHeight: 56,
                        title: Text(c.name),
                        subtitle: Text(
                          '${items.where((i) => i.categoryId == c.id).length} '
                          'dishes${c.isActive ? '' : ' · Hidden from ordering'}',
                        ),
                        trailing: canEdit
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Rename ${c.name}',
                                    icon: const Icon(Icons.edit_outlined),
                                    onPressed: _busy ? null : () => _rename(c),
                                  ),
                                  IconButton(
                                    tooltip: c.isActive
                                        ? 'Hide ${c.name}'
                                        : 'Show ${c.name}',
                                    icon: Icon(
                                      c.isActive
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                    ),
                                    onPressed: _busy
                                        ? null
                                        : () => _run(
                                            (r) => r.updateCategory(
                                              c.id,
                                              isActive: !c.isActive,
                                            ),
                                            c.isActive
                                                ? '${c.name} hidden.'
                                                : '${c.name} showing again.',
                                          ),
                                  ),
                                ],
                              )
                            : null,
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
