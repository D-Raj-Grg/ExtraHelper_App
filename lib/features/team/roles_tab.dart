import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/labels.dart';
import '../../core/theme/tokens.dart';
import '../../data/supabase/team_repository.dart';
import 'role_colors.dart';
import 'team_providers.dart';

/// What each role reaches.
///
/// Split into the seeded roles and the restaurant's own, exactly as the web
/// does — the difference matters, because a default role's name and base role
/// are fixed while its permissions are not.
class RolesTab extends ConsumerWidget {
  const RolesTab({super.key, required this.onOpen, required this.onDelete});

  final void Function(TeamRole role) onOpen;
  final void Function(TeamRole role) onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roles = ref.watch(teamRolesProvider);
    final canEdit = ref.watch(canEditTeamProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(teamRolesProvider),
      child: roles.when(
        loading: () => const _Centered(child: CircularProgressIndicator()),
        error: (e, _) => _LoadFailed(
          error: e,
          onRetry: () => ref.invalidate(teamRolesProvider),
        ),
        data: (all) {
          final system = all.where((r) => r.isSystem).toList();
          final custom = all.where((r) => !r.isSystem).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              _Section(
                title: 'Default roles',
                blurb:
                    'Built in. The name and base role are fixed, but you '
                    'can change what each one reaches.',
                empty: 'This restaurant has no default roles yet.',
                children: [
                  for (final role in system)
                    _RoleCard(
                      role: role,
                      canEdit: canEdit,
                      onOpen: () => onOpen(role),
                      onDelete: null,
                    ),
                ],
              ),
              const SizedBox(height: 24),
              _Section(
                title: 'Custom roles',
                blurb: 'Roles you define for this restaurant.',
                empty:
                    "No custom roles yet. Add one when a default doesn't "
                    'fit — a Shift Lead who can void, say.',
                children: [
                  for (final role in custom)
                    _RoleCard(
                      role: role,
                      canEdit: canEdit,
                      onOpen: () => onOpen(role),
                      onDelete: () => onDelete(role),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.blurb,
    required this.empty,
    required this.children,
  });

  final String title;
  final String blurb;
  final String empty;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          blurb,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        if (children.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(empty, style: theme.textTheme.bodyMedium),
          )
        else
          for (final child in children)
            Padding(padding: const EdgeInsets.only(bottom: 8), child: child),
      ],
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.role,
    required this.canEdit,
    required this.onOpen,
    required this.onDelete,
  });

  final TeamRole role;
  final bool canEdit;
  final VoidCallback onOpen;

  /// Null for a default role — those cannot be deleted, so no control is drawn.
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = role.permissions.length;
    final parts = <String>[
      'Based on ${roleLabel(role.baseRole)}',
      '$count permission${count == 1 ? '' : 's'}',
      // Only when it could actually be read. Never invent a number.
      if (role.countKnown)
        '${role.memberCount} ${role.memberCount == 1 ? 'person' : 'people'}',
    ];

    return Card(
      child: ListTile(
        minTileHeight: Tokens.tapTarget + 12,
        onTap: onOpen,
        leading: Semantics(
          label: roleColorName(role.color),
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: roleColor(role.color),
              shape: BoxShape.circle,
            ),
          ),
        ),
        title: Row(
          children: [
            Flexible(child: Text(role.name, overflow: TextOverflow.ellipsis)),
            if (role.isSystem) ...[
              const SizedBox(width: 8),
              // The word, not a tint — this survives greyscale.
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  border: Border.all(color: theme.colorScheme.outline),
                  borderRadius: BorderRadius.circular(Tokens.radiusSm),
                ),
                child: Text('Default', style: theme.textTheme.labelSmall),
              ),
            ],
          ],
        ),
        subtitle: Text(parts.join(' · ')),
        trailing: canEdit && onDelete != null
            ? IconButton(
                tooltip: 'Delete ${role.name}',
                icon: const Icon(Icons.delete_outline),
                onPressed: onDelete,
              )
            : const Icon(Icons.chevron_right),
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: SizedBox(
        height: constraints.maxHeight,
        child: Center(child: child),
      ),
    ),
  );
}

class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Centered(
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
            Text("Couldn't load that", style: theme.textTheme.titleMedium),
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
