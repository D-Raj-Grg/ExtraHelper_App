import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_scaffold.dart';
import '../../core/format/money.dart';
import '../../core/theme/tokens.dart';
import '../../data/supabase/menu_repository.dart';
import '../../data/supabase/pos_repository.dart' show PosFailure;
import '../pos/pos_providers.dart' show menuProvider;
import '../tenant/tenant_providers.dart';
import 'menu_providers.dart';

Future<void> _run(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function(MenuRepository repo) work,
  String? done,
) async {
  final tenant = ref.read(activeTenantProvider);
  if (tenant == null) return;
  final messenger = ScaffoldMessenger.of(context);
  final container = ProviderScope.containerOf(context, listen: false);
  String? message = done;
  try {
    await work(container.read(menuRepositoryProvider(tenant.tenantId)));
    container.invalidate(menuAddOnsProvider);
    container.invalidate(menuEditItemsProvider);
    // The till reads add-ons with the menu; refresh it so a waiter sees them.
    container.invalidate(menuProvider);
  } on PosFailure catch (e) {
    message = e.message;
  }
  if (message != null) {
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

/// The add-ons a waiter can put on this dish, picked from the restaurant's
/// library. Tick to link, and set how many of each one guest may have.
class ItemAddOnsScreen extends ConsumerWidget {
  const ItemAddOnsScreen({super.key, required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final currency = ref.watch(activeTenantProvider)?.currency ?? 'USD';
    final canEdit = ref.watch(canEditMenuProvider);
    final library = ref.watch(menuAddOnsProvider);
    final item = (ref.watch(menuEditItemsProvider).valueOrNull ?? const [])
        .where((i) => i.id == itemId)
        .firstOrNull;
    final links = {
      for (final l in item?.addOns ?? const <MenuAddOnLink>[]) l.modifierId: l,
    };

    return AppScaffold(
      title: item == null ? 'Add-ons' : 'Add-ons · ${item.name}',
      showDrawer: false,
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: () async {
                final draft = await showAddOnSheet(context, currency: currency);
                if (draft == null || !context.mounted) return;
                await _run(context, ref, (r) async {
                  final id = await r.createAddOn(draft.name, draft.priceCents);
                  await r.linkAddOn(itemId: itemId, modifierId: id);
                }, '${draft.name} added and linked.');
              },
              icon: const Icon(Icons.add),
              label: const Text('New add-on'),
            )
          : null,
      body: library.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (all) => all.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'No add-ons yet. Tap New add-on — extra cheese, no '
                    'onion, a side of rice — and it links to this dish.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                    child: Text(
                      'Ticked add-ons are offered when this dish is ordered. '
                      'The library is shared by every dish.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  for (final a in all)
                    _AddOnRow(
                      key: ValueKey(a.id),
                      addOn: a,
                      link: links[a.id],
                      currency: currency,
                      enabled: canEdit,
                      onToggle: (on) => _run(
                        context,
                        ref,
                        (r) => on
                            ? r.linkAddOn(itemId: itemId, modifierId: a.id)
                            : r.unlinkAddOn(itemId: itemId, modifierId: a.id),
                        null,
                      ),
                      onMaxQty: (q) => _run(
                        context,
                        ref,
                        (r) => r.linkAddOn(
                          itemId: itemId,
                          modifierId: a.id,
                          isDefault: links[a.id]?.isDefault ?? false,
                          maxQty: q,
                        ),
                        null,
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _AddOnRow extends StatelessWidget {
  const _AddOnRow({
    super.key,
    required this.addOn,
    required this.link,
    required this.currency,
    required this.enabled,
    required this.onToggle,
    required this.onMaxQty,
  });

  final MenuAddOn addOn;
  final MenuAddOnLink? link;
  final String currency;
  final bool enabled;
  final ValueChanged<bool> onToggle;
  final ValueChanged<int> onMaxQty;

  @override
  Widget build(BuildContext context) {
    final linked = link != null;
    final qty = link?.maxQty ?? 1;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          CheckboxListTile(
            value: linked,
            onChanged: enabled ? (v) => onToggle(v ?? false) : null,
            title: Text(addOn.name),
            subtitle: Text(
              addOn.priceCents == 0
                  ? 'Free'
                  : '+${money(addOn.priceCents, currency)}',
            ),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          if (linked)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
              child: Row(
                children: [
                  const Expanded(child: Text('Most per dish')),
                  IconButton(
                    tooltip: 'One fewer',
                    constraints: const BoxConstraints(
                      minWidth: Tokens.tapTarget,
                      minHeight: Tokens.tapTarget,
                    ),
                    onPressed: enabled && qty > 1
                        ? () => onMaxQty(qty - 1)
                        : null,
                    icon: const Icon(Icons.remove),
                  ),
                  SizedBox(
                    width: 32,
                    child: Text(
                      '$qty',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'One more',
                    constraints: const BoxConstraints(
                      minWidth: Tokens.tapTarget,
                      minHeight: Tokens.tapTarget,
                    ),
                    onPressed: enabled && qty < 20
                        ? () => onMaxQty(qty + 1)
                        : null,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The add-on library: rename, reprice, delete. Changes apply to every dish
/// the add-on is linked to.
class AddOnsLibraryScreen extends ConsumerWidget {
  const AddOnsLibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(activeTenantProvider)?.currency ?? 'USD';
    final canEdit = ref.watch(canEditMenuProvider);
    final library = ref.watch(menuAddOnsProvider);
    final items = ref.watch(menuEditItemsProvider).valueOrNull ?? const [];

    int uses(String id) =>
        items.where((i) => i.addOns.any((l) => l.modifierId == id)).length;

    return AppScaffold(
      title: 'Add-ons',
      showDrawer: false,
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: () async {
                final d = await showAddOnSheet(context, currency: currency);
                if (d == null || !context.mounted) return;
                await _run(
                  context,
                  ref,
                  (r) => r.createAddOn(d.name, d.priceCents),
                  '${d.name} added. Link it from a dish.',
                );
              },
              icon: const Icon(Icons.add),
              label: const Text('New add-on'),
            )
          : null,
      body: library.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (all) => all.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'No add-ons yet. Add extra cheese, no onion, a side — '
                    'then tick them on each dish that offers them.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                children: [
                  for (final a in all)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        minTileHeight: 56,
                        title: Text(a.name),
                        subtitle: Text(
                          '${a.priceCents == 0 ? 'Free' : '+${money(a.priceCents, currency)}'}'
                          ' · on ${uses(a.id)} '
                          '${uses(a.id) == 1 ? 'dish' : 'dishes'}',
                        ),
                        trailing: canEdit
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Edit ${a.name}',
                                    icon: const Icon(Icons.edit_outlined),
                                    onPressed: () async {
                                      final d = await showAddOnSheet(
                                        context,
                                        currency: currency,
                                        editing: a,
                                      );
                                      if (d == null || !context.mounted) return;
                                      await _run(
                                        context,
                                        ref,
                                        (r) => r.updateAddOn(
                                          a.id,
                                          d.name,
                                          d.priceCents,
                                        ),
                                        'Saved.',
                                      );
                                    },
                                  ),
                                  IconButton(
                                    tooltip: 'Delete ${a.name}',
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: () async {
                                      final ok = await _confirmDelete(
                                        context,
                                        a.name,
                                        uses(a.id),
                                      );
                                      if (ok != true || !context.mounted) {
                                        return;
                                      }
                                      await _run(
                                        context,
                                        ref,
                                        (r) => r.deleteAddOn(a.id),
                                        '${a.name} deleted.',
                                      );
                                    },
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

Future<bool?> _confirmDelete(BuildContext context, String name, int uses) =>
    showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('Delete $name?'),
        content: Text(
          uses == 0
              ? 'It isn’t on any dish. Past orders keep it.'
              : 'It comes off the $uses '
                    '${uses == 1 ? 'dish' : 'dishes'} that offer it. Past '
                    'orders keep it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: const Text('Delete add-on'),
          ),
        ],
      ),
    );

/// An add-on as typed.
class AddOnDraft {
  const AddOnDraft(this.name, this.priceCents);

  final String name;
  final int priceCents;
}

/// Name and price for an add-on. Owns its controllers.
Future<AddOnDraft?> showAddOnSheet(
  BuildContext context, {
  required String currency,
  MenuAddOn? editing,
}) => showModalBottomSheet<AddOnDraft>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (sheet) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.of(sheet).viewInsets.bottom),
    child: _AddOnSheet(currency: currency, editing: editing),
  ),
);

class _AddOnSheet extends StatefulWidget {
  const _AddOnSheet({required this.currency, this.editing});

  final String currency;
  final MenuAddOn? editing;

  @override
  State<_AddOnSheet> createState() => _AddOnSheetState();
}

class _AddOnSheetState extends State<_AddOnSheet> {
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
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    final raw = _price.text.trim();
    final v = raw.isEmpty ? 0.0 : double.tryParse(raw);
    if (name.isEmpty) return setState(() => _error = 'Give it a name.');
    if (v == null || v < 0) {
      return setState(() => _error = 'Price must be 0 or more.');
    }
    Navigator.of(context).pop(AddOnDraft(name, (v * 100).round()));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.editing == null ? 'New add-on' : 'Edit add-on',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'Extra cheese',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: InputDecoration(
                labelText: 'Price (${widget.currency})',
                hintText: '0 for free',
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _submit,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
