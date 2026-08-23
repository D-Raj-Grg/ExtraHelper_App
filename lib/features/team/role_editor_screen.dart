import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_scaffold.dart';
import '../../core/format/labels.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/choice_chip.dart';
import '../../data/supabase/team_repository.dart';
import '../tenant/tenant_providers.dart';
import 'role_colors.dart';
import 'team_providers.dart';

/// Create or edit a role, including what it reaches.
///
/// **A pushed screen, not a sheet.** Thirty-seven checkboxes in seven groups,
/// plus a name, a description, a base role and twelve swatches, do not fit in a
/// modal on a 360x640 phone — and the keyboard would cover the first two fields
/// the moment they are tapped. This is a deliberate exception to "a sheet pops a
/// draft and the caller writes": that rule exists so a controller never outlives
/// its `State`, and a pushed screen owns both. It also has to own the write,
/// because a failed save must leave the form exactly as typed, which a popped
/// draft cannot do.
class RoleEditorScreen extends ConsumerStatefulWidget {
  const RoleEditorScreen({super.key, this.role});

  /// Null to create.
  final TeamRole? role;

  @override
  ConsumerState<RoleEditorScreen> createState() => _RoleEditorScreenState();
}

class _RoleEditorScreenState extends ConsumerState<RoleEditorScreen> {
  late final TextEditingController _name = TextEditingController(
    text: widget.role?.name ?? '',
  );
  late final TextEditingController _description = TextEditingController(
    text: widget.role?.description ?? '',
  );

  late String _color = widget.role?.color ?? kDefaultRoleColor;
  late String _baseRole = widget.role?.baseRole ?? 'waiter';
  late final Set<String> _selected = {...?widget.role?.permissions};

  bool _saving = false;
  String? _error;

  /// A default role's name and base role are what the seeded RLS floor keys
  /// off. Its permissions are still the restaurant's to tune.
  bool get _identityLocked => widget.role?.isSystem ?? false;

  bool get _valid =>
      _name.text.trim().isNotEmpty &&
      kBaseRoles.contains(_baseRole) &&
      !_saving;

  /// An owner-based role that loses `staff.edit` locks every owner out of this
  /// screen for good, with SQL as the only way back. Held in three places: here,
  /// in the disabled checkbox, and in [RoleDraft.effectivePermissions].
  bool _pinned(String key) => _baseRole == 'owner' && key == 'staff.edit';

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groups = ref.watch(permissionGroupsProvider);
    final catalog = ref.watch(permissionCatalogProvider);
    final isNew = widget.role == null;
    final effective = _selected.length + (_pinnedMissing ? 1 : 0);

    return AppScaffold(
      title: isNew ? 'New role' : widget.role!.name,
      showDrawer: false,
      body: catalog.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _CatalogFailed(
          error: e,
          onRetry: () => ref.invalidate(permissionCatalogProvider),
        ),
        data: (_) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            if (_identityLocked) ...[
              Text(
                'A default role. Its name and base role are fixed, but you '
                'can change what it reaches.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: _name,
              enabled: !_identityLocked,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'e.g. Shift Lead',
                constraints: BoxConstraints(minHeight: Tokens.tapTarget),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              enabled: !_identityLocked,
              decoration: const InputDecoration(
                labelText: 'Description',
                hintText: 'What this role is for',
                constraints: BoxConstraints(minHeight: Tokens.tapTarget),
              ),
            ),
            const SizedBox(height: 20),
            Text('Base role', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final base in kBaseRoles)
                  AppChoiceChip(
                    label: roleLabel(base),
                    selected: _baseRole == base,
                    showCheck: true,
                    enabled: !_identityLocked,
                    onSelect: () => setState(() => _baseRole = base),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'The database access floor enforced by row-level security. '
              "Permissions only ever narrow what this allows — they can't "
              'widen it.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            Text('Colour', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            _Swatches(
              selected: _color,
              enabled: !_identityLocked,
              onSelect: (hex) => setState(() => _color = hex),
            ),
            const SizedBox(height: 24),
            Text(
              'Permissions ($effective selected)',
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            for (final group in groups) _buildGroup(group),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error != null) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Icon as well as tint: a failure that is only a colour is
                    // invisible in greyscale.
                    Icon(
                      Icons.error_outline,
                      size: 16,
                      color: context.semantic.dangerText,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: context.semantic.dangerText,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _valid ? _save : null,
                  child: Text(
                    _saving
                        ? 'Saving…'
                        : (isNew ? 'Create role' : 'Save changes'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _pinnedMissing =>
      _baseRole == 'owner' && !_selected.contains('staff.edit');

  Widget _buildGroup(PermissionGroup group) {
    final keys = [for (final def in group.items) def.key];
    final chosen = keys.where(_isOn).length;
    return ExpansionTile(
      // Collapsed by default, except where something is already on —
      // thirty-seven expanded rows is four screens of scrolling.
      initiallyExpanded: chosen > 0,
      title: Text(group.grp),
      subtitle: Text('$chosen of ${keys.length}'),
      childrenPadding: const EdgeInsets.only(bottom: 8),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => _setGroup(keys, on: true),
              child: const Text('Select all'),
            ),
            TextButton(
              onPressed: () => _setGroup(keys, on: false),
              child: const Text('Clear'),
            ),
          ],
        ),
        for (final def in group.items)
          CheckboxListTile(
            controlAffinity: ListTileControlAffinity.trailing,
            // The whole row is the target, not a 16dp box.
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            value: _isOn(def.key),
            onChanged: _pinned(def.key)
                ? null
                : (on) => setState(() {
                    if (on ?? false) {
                      _selected.add(def.key);
                    } else {
                      _selected.remove(def.key);
                    }
                  }),
            title: Text(def.label),
            subtitle: Text(_pinned(def.key) ? 'Always on for owners' : def.key),
          ),
      ],
    );
  }

  bool _isOn(String key) => _pinned(key) || _selected.contains(key);

  void _setGroup(List<String> keys, {required bool on}) => setState(() {
    for (final key in keys) {
      // Clear must never take the pin with it.
      if (_pinned(key)) continue;
      if (on) {
        _selected.add(key);
      } else {
        _selected.remove(key);
      }
    }
  });

  Future<void> _save() async {
    final tenant = ref.read(activeTenantProvider);
    if (tenant == null || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    final draft = RoleDraft(
      name: _name.text,
      description: _description.text,
      color: _color,
      baseRole: _baseRole,
      permissions: _selected,
    );
    final repo = ref.read(teamRepositoryProvider(tenant.tenantId));
    final isNew = widget.role == null;

    try {
      if (isNew) {
        await repo.createRole(draft);
      } else {
        await repo.updateRole(widget.role!.id, draft);
      }
      ref.invalidate(teamRolesProvider);
      // Editing your own role changes what you reach *now*. Without this an
      // owner can drop their own `menu.edit` and keep seeing the menu button
      // until they relaunch.
      ref.invalidate(permissionsProvider);
      if (!mounted) return;
      Navigator.of(
        context,
      ).pop(isNew ? 'Role created.' : '${draft.name.trim()} updated.');
    } on Object catch (e) {
      // Deliberately does not pop: the selection stays exactly as typed.
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _Swatches extends StatelessWidget {
  const _Swatches({
    required this.selected,
    required this.enabled,
    required this.onSelect,
  });

  final String selected;
  final bool enabled;
  final void Function(String hex) onSelect;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final swatch in kRoleColors)
        Semantics(
          button: true,
          selected: swatch.hex == selected,
          enabled: enabled,
          label: swatch.name,
          child: ExcludeSemantics(
            child: Opacity(
              opacity: enabled ? 1 : 0.5,
              child: InkWell(
                onTap: enabled ? () => onSelect(swatch.hex) : null,
                borderRadius: BorderRadius.circular(Tokens.radiusMd),
                child: Container(
                  width: Tokens.tapTarget,
                  height: Tokens.tapTarget,
                  decoration: BoxDecoration(
                    color: roleColor(swatch.hex),
                    borderRadius: BorderRadius.circular(Tokens.radiusMd),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outline,
                      width: swatch.hex == selected ? 3 : 1,
                    ),
                  ),
                  // Selection is never fill alone.
                  child: swatch.hex == selected
                      ? const Icon(Icons.check, color: Colors.white, size: 20)
                      : null,
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

class _CatalogFailed extends StatelessWidget {
  const _CatalogFailed({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 40,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              "Couldn't load the permission list",
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              '$error',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
