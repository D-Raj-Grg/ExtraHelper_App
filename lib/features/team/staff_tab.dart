import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/labels.dart';
import '../../core/theme/tokens.dart';
import '../../data/supabase/team_repository.dart';
import '../pos/order_composer.dart' show PosEmptyState;
import 'team_providers.dart';

/// What a row's overflow menu can do. Named rather than raw strings so the
/// switch in the screen is exhaustive.
enum MemberAction { changeRole, approve, remove, cancelInvite }

/// Who is on the team.
class StaffTab extends ConsumerWidget {
  const StaffTab({super.key, required this.onAction, required this.onJoinCode});

  final void Function(TeamMember member, MemberAction action) onAction;
  final VoidCallback onJoinCode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(teamMembersProvider);
    final canEdit = ref.watch(canEditTeamProvider);
    final myUserId = ref.watch(myUserIdProvider);
    final owners = ref.watch(ownerCountProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(teamMembersProvider),
      child: members.when(
        loading: () => const _Centered(child: CircularProgressIndicator()),
        error: (e, _) => _LoadFailed(
          error: e,
          onRetry: () => ref.invalidate(teamMembersProvider),
        ),
        data: (roster) {
          if (roster.isEmpty) return _Empty(canEdit: canEdit);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              if (canEdit) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: onJoinCode,
                    icon: const Icon(Icons.key_outlined),
                    label: const Text('Join code'),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              for (final member in roster)
                _MemberRow(
                  member: member,
                  canEdit: canEdit,
                  isMe: member.userId != null && member.userId == myUserId,
                  isLastOwner: member.isOwner && owners <= 1,
                  onAction: (action) => onAction(member, action),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.canEdit,
    required this.isMe,
    required this.isLastOwner,
    required this.onAction,
  });

  final TeamMember member;
  final bool canEdit;

  /// `remove_member` refuses self-removal, so the control is never offered.
  final bool isMe;

  /// The server refuses to remove or demote the last owner. Pre-empted here so
  /// the answer arrives before the tap rather than after it.
  final bool isLastOwner;

  final void Function(MemberAction action) onAction;

  @override
  Widget build(BuildContext context) {
    final items = <PopupMenuEntry<MemberAction>>[
      if (!member.isInvite)
        const PopupMenuItem(
          value: MemberAction.changeRole,
          child: Text('Change role'),
        ),
      if (member.isPending && !member.isInvite)
        const PopupMenuItem(
          value: MemberAction.approve,
          child: Text('Approve'),
        ),
      if (member.isInvite)
        const PopupMenuItem(
          value: MemberAction.cancelInvite,
          child: Text('Cancel invite'),
        )
      else if (!isMe && !isLastOwner)
        const PopupMenuItem(value: MemberAction.remove, child: Text('Remove')),
    ];

    return ListTile(
      minTileHeight: Tokens.tapTarget + 12,
      contentPadding: EdgeInsets.zero,
      leading: _StatusPill(status: member.status),
      title: Text(member.email, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${member.roleDisplay} · ${memberStatusLabel(member.status)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      // A disabled menu invites a tap that goes nowhere.
      trailing: canEdit && items.isNotEmpty
          ? PopupMenuButton<MemberAction>(
              tooltip: 'Actions for ${member.email}',
              onSelected: onAction,
              itemBuilder: (context) => items,
            )
          : null,
    );
  }
}

/// Icon **and** label, never colour alone — the status word is already in the
/// subtitle, so the tint is redundant by design.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    final (icon, color) = switch (status) {
      'active' => (Icons.check_circle_outline, semantic.goodText),
      'pending' => (Icons.hourglass_empty, semantic.warningText),
      'invited' => (Icons.mail_outline, semantic.infoText),
      _ => (Icons.person_outline, semantic.neutral),
    };
    return Semantics(
      label: memberStatusLabel(status),
      child: Icon(icon, color: color),
    );
  }
}

/// The empty roster is two different facts wearing the same clothes.
///
/// `list_tenant_members` filters rather than raises, so someone who cannot read
/// the roster gets `[]` — identical to a genuinely empty restaurant. Telling
/// them "no team members yet" would be repeating a lie the server told by
/// omission.
class _Empty extends StatelessWidget {
  const _Empty({required this.canEdit});

  final bool canEdit;

  @override
  Widget build(BuildContext context) => _Centered(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: canEdit
          ? const PosEmptyState(
              icon: Icons.group_add_outlined,
              title: 'No one here yet',
              body: 'Add someone by email, or hand them a join code.',
            )
          : const PosEmptyState(
              icon: Icons.lock_outline,
              title: "The roster isn't shown to your role",
              body: 'Only someone who can manage the team sees who is on it.',
            ),
    ),
  );
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
            Text("Couldn't load your team", style: theme.textTheme.titleMedium),
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
