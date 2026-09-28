import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_scaffold.dart';
import '../../core/format/money.dart';
import '../../core/theme/tokens.dart';
import '../../data/supabase/menu_repository.dart';
import '../../data/supabase/pos_repository.dart' show PosFailure;
import '../tenant/tenant_providers.dart';
import 'menu_providers.dart';

/// Combos: several dishes at one price ("Lunch set: momo, tea"). The same
/// `combos` rows the web editor writes, `items` as `[{item_id, qty}]`.
class CombosScreen extends ConsumerStatefulWidget {
  const CombosScreen({super.key});

  @override
  ConsumerState<CombosScreen> createState() => _CombosScreenState();
}

class _CombosScreenState extends ConsumerState<CombosScreen> {
  bool _busy = false;

  Future<void> _run(
    Future<void> Function(MenuRepository r) work,
    String done,
  ) async {
    final tenant = ref.read(activeTenantProvider);
    if (tenant == null || _busy) return;
    setState(() => _busy = true);
    String message;
    try {
      await work(ref.read(menuRepositoryProvider(tenant.tenantId)));
      message = done;
      ref.invalidate(menuCombosProvider);
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

  Future<void> _edit(List<MenuEditItem> dishes, {MenuCombo? combo}) async {
    final currency = ref.read(activeTenantProvider)?.currency ?? 'USD';
    final draft = await showModalBottomSheet<_ComboDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheet) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheet).viewInsets.bottom,
        ),
        child: _ComboSheet(dishes: dishes, currency: currency, editing: combo),
      ),
    );
    if (draft == null) return;
    await _run(
      (r) => r.saveCombo(
        id: combo?.id,
        name: draft.name,
        priceCents: draft.priceCents,
        items: draft.items,
      ),
      combo == null ? '${draft.name} added.' : 'Saved.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currency = ref.watch(activeTenantProvider)?.currency ?? 'USD';
    final canEdit = ref.watch(canEditMenuProvider);
    final combos = ref.watch(menuCombosProvider);
    final dishes = ref.watch(menuEditItemsProvider).valueOrNull ?? const [];
    final byId = {for (final d in dishes) d.id: d};

    return AppScaffold(
      title: 'Combos',
      showDrawer: false,
      floatingActionButton: canEdit && dishes.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _busy ? null : () => _edit(dishes),
              icon: const Icon(Icons.add),
              label: const Text('New combo'),
            )
          : null,
      body: combos.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (all) => all.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'No combos yet. Bundle dishes at one price — a lunch '
                    'set of momo and tea, a family platter.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                children: [
                  for (final c in all)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    c.name,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    c.items
                                        .map(
                                          (i) =>
                                              '${i.qty}× ${byId[i.itemId]?.name ?? 'Deleted dish'}',
                                        )
                                        .join(', '),
                                    style: theme.textTheme.bodySmall,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${money(c.priceCents, currency)}'
                                    '${c.isActive ? '' : ' · Off'}',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (canEdit) ...[
                              Switch(
                                value: c.isActive,
                                onChanged: _busy
                                    ? null
                                    : (v) => _run(
                                        (r) => r.setComboActive(c.id, v),
                                        v
                                            ? '${c.name} is on.'
                                            : '${c.name} is off.',
                                      ),
                              ),
                              PopupMenuButton<String>(
                                tooltip: 'Actions for ${c.name}',
                                onSelected: (v) async {
                                  if (v == 'edit') {
                                    await _edit(dishes, combo: c);
                                    return;
                                  }
                                  final ok = await showDialog<bool>(
                                    context: context,
                                    builder: (d) => AlertDialog(
                                      title: Text('Delete ${c.name}?'),
                                      content: const Text(
                                        'The dishes in it stay on the menu.',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.of(d).pop(false),
                                          child: const Text('Keep it'),
                                        ),
                                        FilledButton.tonal(
                                          onPressed: () =>
                                              Navigator.of(d).pop(true),
                                          child: const Text('Delete combo'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (ok == true) {
                                    await _run(
                                      (r) => r.deleteCombo(c.id),
                                      '${c.name} deleted.',
                                    );
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: ListTile(
                                      leading: Icon(Icons.edit_outlined),
                                      title: Text('Edit'),
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: ListTile(
                                      leading: Icon(Icons.delete_outline),
                                      title: Text('Delete'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _ComboDraft {
  const _ComboDraft(this.name, this.priceCents, this.items);

  final String name;
  final int priceCents;
  final List<({String itemId, int qty})> items;
}

class _ComboSheet extends StatefulWidget {
  const _ComboSheet({
    required this.dishes,
    required this.currency,
    this.editing,
  });

  final List<MenuEditItem> dishes;
  final String currency;
  final MenuCombo? editing;

  @override
  State<_ComboSheet> createState() => _ComboSheetState();
}

class _ComboSheetState extends State<_ComboSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.editing?.name ?? '',
  );
  late final TextEditingController _price = TextEditingController(
    text: widget.editing == null
        ? ''
        : (widget.editing!.priceCents / 100).toStringAsFixed(
            widget.editing!.priceCents % 100 == 0 ? 0 : 2,
          ),
  );
  final _search = TextEditingController();

  /// Dish id → how many are in the combo. Insertion order is kept.
  late final Map<String, int> _qty = {
    for (final i
        in widget.editing?.items ?? const <({String itemId, int qty})>[])
      i.itemId: i.qty,
  };
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _search.dispose();
    super.dispose();
  }

  int get _sumCents => _qty.entries.fold(0, (s, e) {
    final d = widget.dishes.where((x) => x.id == e.key).firstOrNull;
    return s + (d?.basePriceCents ?? 0) * e.value;
  });

  void _submit() {
    final name = _name.text.trim();
    final v = double.tryParse(_price.text.trim());
    if (name.isEmpty) return setState(() => _error = 'Give the combo a name.');
    if (v == null || v < 0) {
      return setState(() => _error = 'Enter the combo price.');
    }
    if (_qty.isEmpty) {
      return setState(() => _error = 'Add at least one dish.');
    }
    Navigator.of(context).pop(
      _ComboDraft(name, (v * 100).round(), [
        for (final e in _qty.entries) (itemId: e.key, qty: e.value),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = _search.text.trim().toLowerCase();
    final list = q.isEmpty
        ? widget.dishes
        : widget.dishes.where((d) => d.name.toLowerCase().contains(q)).toList();

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.85,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.editing == null ? 'New combo' : 'Edit combo',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Name',
                          hintText: 'Lunch set',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _price,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                        ],
                        decoration: InputDecoration(
                          labelText: 'Price (${widget.currency})',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _qty.isEmpty
                      ? 'Pick the dishes below.'
                      : '${_qty.values.fold(0, (a, b) => a + b)} dishes · '
                            '${money(_sumCents, widget.currency)} if bought '
                            'separately',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Find a dish',
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                for (final d in list)
                  ListTile(
                    key: ValueKey(d.id),
                    title: Text(d.name),
                    subtitle: Text(money(d.basePriceCents, widget.currency)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'One fewer ${d.name}',
                          constraints: const BoxConstraints(
                            minWidth: Tokens.tapTarget,
                            minHeight: Tokens.tapTarget,
                          ),
                          onPressed: (_qty[d.id] ?? 0) == 0
                              ? null
                              : () => setState(() {
                                  final n = _qty[d.id]! - 1;
                                  n == 0 ? _qty.remove(d.id) : _qty[d.id] = n;
                                }),
                          icon: const Icon(Icons.remove),
                        ),
                        SizedBox(
                          width: 28,
                          child: Text(
                            '${_qty[d.id] ?? 0}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'One more ${d.name}',
                          constraints: const BoxConstraints(
                            minWidth: Tokens.tapTarget,
                            minHeight: Tokens.tapTarget,
                          ),
                          onPressed: () => setState(
                            () => _qty[d.id] = (_qty[d.id] ?? 0) + 1,
                          ),
                          icon: const Icon(Icons.add),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _error!,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  FilledButton(
                    onPressed: _submit,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    child: const Text('Save combo'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
