import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_scaffold.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/choice_chip.dart';
import '../../core/widgets/dish_thumb.dart';
import '../../core/widgets/photo_picker.dart';
import '../../core/widgets/veg_mark.dart';
import '../../data/supabase/menu_repository.dart';
import '../../data/supabase/pos_repository.dart' show PosFailure;
import '../pos/pos_providers.dart' show menuProvider;
import '../tenant/tenant_providers.dart';
import 'item_addons_screen.dart';
import 'item_availability_screen.dart';
import 'item_variants_screen.dart';
import 'menu_providers.dart';
import 'stock_toggle.dart';

/// Add a dish, or change one: photo, name, price, category, kitchen station,
/// veg mark, description, stock, and a way into its sizes.
///
/// Held by id and re-read from the live list, so a save or a stock change
/// elsewhere shows up without reopening. [itemId] null means "new dish".
class ItemEditScreen extends ConsumerStatefulWidget {
  const ItemEditScreen({super.key, this.itemId});

  final String? itemId;

  @override
  ConsumerState<ItemEditScreen> createState() => _ItemEditScreenState();
}

class _ItemEditScreenState extends ConsumerState<ItemEditScreen> {
  late final TextEditingController _name;
  late final TextEditingController _price;
  late final TextEditingController _cost;
  late final TextEditingController _description;
  String? _categoryId;
  Set<String> _stationIds = {};
  bool? _isVeg;
  bool _seeded = false;
  bool _busy = false;
  String? _error;

  /// Picked for a dish that doesn't exist yet; uploaded right after the insert.
  PickedPhoto? _pendingPhoto;

  String? _id;

  @override
  void initState() {
    super.initState();
    _id = widget.itemId;
    _name = TextEditingController();
    _price = TextEditingController();
    _cost = TextEditingController();
    _description = TextEditingController();
    if (_id == null) _seeded = true;
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _cost.dispose();
    _description.dispose();
    super.dispose();
  }

  /// Fill the form once, from the first copy of the row we see.
  void _seed(MenuEditItem item) {
    if (_seeded) return;
    _seeded = true;
    _name.text = item.name;
    _price.text = _plain(item.basePriceCents);
    _cost.text = item.costCents == null ? '' : _plain(item.costCents!);
    _description.text = item.description ?? '';
    _categoryId = item.categoryId;
    _stationIds = item.stationIds.toSet();
    _isVeg = item.isVeg;
  }

  static String _plain(int cents) => cents % 100 == 0
      ? (cents ~/ 100).toString()
      : (cents / 100).toStringAsFixed(2);

  static int? _cents(String raw) {
    final v = double.tryParse(raw.trim());
    if (v == null || v < 0) return null;
    return (v * 100).round();
  }

  MenuRepository? get _repo {
    final tenant = ref.read(activeTenantProvider);
    return tenant == null
        ? null
        : ref.read(menuRepositoryProvider(tenant.tenantId));
  }

  void _say(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  void _refreshLists() {
    ref.invalidate(menuEditItemsProvider);
    // The till caches the menu; refresh it so a new dish or price shows there.
    ref.invalidate(menuProvider);
  }

  Future<void> _save() async {
    final repo = _repo;
    if (repo == null || _busy) return;
    final name = _name.text.trim();
    final cents = _cents(_price.text);
    if (name.isEmpty) return setState(() => _error = 'Give the dish a name.');
    if (cents == null) {
      return setState(() => _error = 'Enter a price — 0 is allowed.');
    }
    // Only someone who saw the field may write it; otherwise the stored cost
    // is left alone rather than cleared by a form that never showed it.
    final canSeeProfit = ref.read(hasPermissionProvider('profit.view'));
    final costRaw = _cost.text.trim();
    final costCents = costRaw.isEmpty ? null : _cents(costRaw);
    if (canSeeProfit && costRaw.isNotEmpty && costCents == null) {
      return setState(() => _error = 'Enter a cost price, or leave it blank.');
    }
    final draft = MenuItemDraft(
      name: name,
      basePriceCents: cents,
      categoryId: _categoryId,
      description: _description.text,
      isVeg: _isVeg,
      stationIds: _stationIds,
      costCents: costCents,
      costSet: canSeeProfit,
    );
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = _id;
      if (id == null) {
        final created = await repo.createItem(draft);
        final newId = created.id;
        _id = newId;
        _refreshLists();
        final photo = _pendingPhoto;
        if (photo != null) {
          try {
            await repo.uploadItemPhoto(
              itemId: newId,
              bytes: Uint8List.fromList(photo.bytes),
              ext: photo.ext,
              contentType: photo.contentType,
            );
            _pendingPhoto = null;
            _refreshLists();
          } on PosFailure catch (e) {
            // The dish exists now; stay here so the photo can be retried with
            // Change photo, rather than losing it behind a closed screen.
            if (mounted) {
              setState(
                () => _error =
                    '$name is on the menu, but the photo didn’t upload: '
                    '${e.message} Tap Change photo to try again.',
              );
            }
            return;
          }
        }
        final costWarning = created.costWarning;
        if (costWarning != null) {
          // Same shape as the photo: the dish exists, so stay here. `_id` is
          // set now, so the next Save goes through updateItem and retries the
          // cost against the row that already exists.
          if (mounted) {
            setState(() => _error = '$costWarning Tap Save to try again.');
          }
          return;
        }
        _say('$name added to the menu.');
        if (mounted) Navigator.of(context).pop();
        return;
      }
      await repo.updateItem(id, draft);
      _refreshLists();
      _say('Saved.');
      if (mounted) Navigator.of(context).pop();
    } on PosFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changePhoto() async {
    final photo = await pickPhoto(context);
    if (photo == null || !mounted) return;
    final id = _id;
    if (id == null) {
      setState(() => _pendingPhoto = photo);
      return;
    }
    final repo = _repo;
    if (repo == null) return;
    setState(() => _busy = true);
    try {
      await repo.uploadItemPhoto(
        itemId: id,
        bytes: Uint8List.fromList(photo.bytes),
        ext: photo.ext,
        contentType: photo.contentType,
      );
      _refreshLists();
      _say('Photo updated.');
    } on PosFailure catch (e) {
      _say(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removePhoto() async {
    final id = _id;
    if (id == null) {
      setState(() => _pendingPhoto = null);
      return;
    }
    final repo = _repo;
    if (repo == null) return;
    setState(() => _busy = true);
    try {
      await repo.removeItemPhoto(id);
      _refreshLists();
      _say('Photo removed.');
    } on PosFailure catch (e) {
      _say(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _newCategory() async {
    final repo = _repo;
    if (repo == null) return;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _NameDialog(title: 'New category'),
    );
    if (name == null) return;
    try {
      final id = await repo.createCategory(name);
      ref.invalidate(menuCategoriesProvider);
      if (mounted) setState(() => _categoryId = id);
    } on PosFailure catch (e) {
      _say(e.message);
    }
  }

  Future<void> _delete(MenuEditItem item) async {
    final repo = _repo;
    if (repo == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('Delete ${item.name}?'),
        content: const Text(
          'It disappears from the POS, QR and online menus, together with its '
          'sizes, add-on links, time windows and recipe. Past orders and bills '
          'keep it. To stop selling it for today only, mark it sold out '
          'instead.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: const Text('Delete dish'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await repo.deleteItem(item.id);
      _refreshLists();
      _say('${item.name} deleted.');
      if (mounted) Navigator.of(context).pop();
    } on PosFailure catch (e) {
      _say(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currency = ref.watch(activeTenantProvider)?.currency ?? 'USD';
    final canEdit = ref.watch(canEditMenuProvider);
    final canSeeProfit = ref.watch(hasPermissionProvider('profit.view'));
    final categories =
        ref.watch(menuCategoriesProvider).valueOrNull ?? const [];
    final stations = ref.watch(menuStationsProvider).valueOrNull ?? const [];
    final id = _id;
    final item = id == null
        ? null
        : (ref.watch(menuEditItemsProvider).valueOrNull ?? const [])
              .where((i) => i.id == id)
              .firstOrNull;
    if (item != null) _seed(item);
    if (id != null && item == null && !_seeded) {
      return const AppScaffold(
        title: 'Dish',
        showDrawer: false,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return AppScaffold(
      title: id == null ? 'New dish' : 'Edit dish',
      showDrawer: false,
      actions: [
        if (item != null && canEdit)
          IconButton(
            tooltip: 'Delete dish',
            icon: const Icon(Icons.delete_outline),
            onPressed: _busy ? null : () => _delete(item),
          ),
      ],
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        children: [
          AbsorbPointer(
            absorbing: !canEdit,
            child: _PhotoCard(
              name: _name.text.isEmpty ? (item?.name ?? '?') : _name.text,
              imageUrl: item?.imageUrl,
              pending: _pendingPhoto,
              busy: _busy,
              onChange: _changePhoto,
              onRemove: (item?.imageUrl != null || _pendingPhoto != null)
                  ? _removePhoto
                  : null,
            ),
          ),
          // Outside the read-only lock: the kitchen may change stock without
          // being allowed to edit the dish.
          if (item != null) ...[
            const SizedBox(height: 12),
            StockToggleTile(item: item),
          ],
          const SizedBox(height: 16),
          AbsorbPointer(
            absorbing: !canEdit,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Dish name',
                    hintText: 'Buff Sekuwa',
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
                  style: const TextStyle(
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                  decoration: InputDecoration(
                    labelText: 'Price ($currency)',
                    helperText: item != null && item.variants.isNotEmpty
                        ? 'Base price. Each size adds or takes away from it.'
                        : null,
                    border: const OutlineInputBorder(),
                  ),
                ),
                if (canSeeProfit) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _cost,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    style: const TextStyle(
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                    decoration: InputDecoration(
                      labelText: 'Cost price ($currency)',
                      helperText:
                          'What it costs you to make. Used for profit reports.',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                _Label('Category'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    AppChoiceChip(
                      label: 'None',
                      selected: _categoryId == null,
                      showCheck: true,
                      onSelect: () => setState(() => _categoryId = null),
                    ),
                    for (final c in categories)
                      AppChoiceChip(
                        label: c.name,
                        detail: c.isActive ? null : 'Hidden',
                        selected: _categoryId == c.id,
                        showCheck: true,
                        onSelect: () => setState(() => _categoryId = c.id),
                      ),
                    ActionChip(
                      avatar: const Icon(Icons.add, size: 18),
                      label: const Text('New category'),
                      onPressed: _newCategory,
                    ),
                  ],
                ),
                if (stations.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _Label('Kitchen stations'),
                  Text(
                    'Its ticket goes to every station picked — a dish plated at '
                    'the grill and garnished at the bar can go to both.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final s in stations)
                        AppChoiceChip(
                          label: s.name,
                          selected: _stationIds.contains(s.id),
                          showCheck: true,
                          onSelect: () => setState(() {
                            _stationIds = {..._stationIds};
                            if (!_stationIds.remove(s.id)) {
                              _stationIds.add(s.id);
                            }
                          }),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                _Label('Veg or non-veg'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    AppChoiceChip(
                      label: 'Veg',
                      leading: const VegMark(isVeg: true),
                      selected: _isVeg == true,
                      showCheck: true,
                      onSelect: () => setState(() => _isVeg = true),
                    ),
                    AppChoiceChip(
                      label: 'Non-veg',
                      leading: const VegMark(isVeg: false),
                      selected: _isVeg == false,
                      showCheck: true,
                      onSelect: () => setState(() => _isVeg = false),
                    ),
                    AppChoiceChip(
                      label: 'Not marked',
                      selected: _isVeg == null,
                      showCheck: true,
                      onSelect: () => setState(() => _isVeg = null),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _description,
                  maxLines: 3,
                  minLines: 2,
                  maxLength: 300,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                    hintText: 'Shown on the QR and online menu',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          if (item != null) ...[
            const SizedBox(height: 4),
            _LinkTile(
              icon: Icons.add_circle_outline,
              title: 'Add-ons',
              subtitle: item.addOns.isEmpty
                  ? 'None — extra cheese, no onion, a side'
                  : '${item.addOns.length} linked',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ItemAddOnsScreen(itemId: item.id),
                ),
              ),
            ),
            const SizedBox(height: 8),
            _LinkTile(
              icon: Icons.schedule,
              title: 'When it’s sold',
              subtitle: item.availability.isEmpty
                  ? 'Any time'
                  : item.availability
                        .map((a) => '${a.dayLabel} ${a.window}')
                        .join(' · '),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ItemAvailabilityScreen(itemId: item.id),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                minTileHeight: 56,
                leading: const Icon(Icons.straighten),
                title: const Text('Sizes & variants'),
                subtitle: Text(
                  item.variants.isEmpty
                      ? 'None — one price'
                      : item.variants.map((v) => v.name).join(', '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ItemVariantsScreen(itemId: item.id),
                  ),
                ),
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          if (!canEdit) ...[
            const SizedBox(height: 16),
            Text(
              'You can see this dish but not change it.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
      bottomNavigationBar: canEdit
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: _busy ? null : _save,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  icon: _busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: Text(id == null ? 'Add to menu' : 'Save changes'),
                ),
              ),
            )
          : null,
    );
  }
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: ListTile(
      minTileHeight: 56,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    ),
  );
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: Theme.of(context).textTheme.labelLarge),
  );
}

class _PhotoCard extends StatelessWidget {
  const _PhotoCard({
    required this.name,
    required this.imageUrl,
    required this.pending,
    required this.busy,
    required this.onChange,
    required this.onRemove,
  });

  final String name;
  final String? imageUrl;
  final PickedPhoto? pending;
  final bool busy;
  final VoidCallback onChange;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = pending != null || (imageUrl?.isNotEmpty ?? false);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox.square(
            dimension: 112,
            child: pending != null
                ? Image.memory(
                    Uint8List.fromList(pending!.bytes),
                    fit: BoxFit.cover,
                  )
                : DishThumb(name: name, imageUrl: imageUrl, monogramSize: 36),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(Tokens.tapTarget),
                ),
                onPressed: busy ? null : onChange,
                icon: const Icon(Icons.add_a_photo_outlined),
                label: Text(hasPhoto ? 'Change photo' : 'Add photo'),
              ),
              if (onRemove != null) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    minimumSize: const Size.fromHeight(Tokens.tapTarget),
                  ),
                  onPressed: busy ? null : onRemove,
                  icon: const Icon(Icons.hide_image_outlined),
                  label: const Text('Remove photo'),
                ),
              ],
              if (pending != null)
                Text(
                  'Uploads when you add the dish.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, this.initial = ''});

  final String title;
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _c = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _c,
      autofocus: true,
      textCapitalization: TextCapitalization.words,
      decoration: const InputDecoration(
        labelText: 'Name',
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
        onPressed: _c.text.trim().isEmpty
            ? null
            : () => Navigator.of(context).pop(_c.text.trim()),
        child: const Text('Save'),
      ),
    ],
  );
}

/// Exposed for the categories screen, which asks for a name the same way.
Future<String?> showMenuNameDialog(
  BuildContext context, {
  required String title,
  String initial = '',
}) => showDialog<String>(
  context: context,
  builder: (_) => _NameDialog(title: title, initial: initial),
);
