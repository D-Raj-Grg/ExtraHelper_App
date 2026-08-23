import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_scaffold.dart';
import '../../data/supabase/team_repository.dart';
import '../tenant/tenant_providers.dart';
import 'add_member_sheet.dart';
import 'join_code_sheet.dart';
import 'role_editor_screen.dart';
import 'role_picker_sheet.dart';
import 'roles_tab.dart';
import 'staff_tab.dart';
import 'team_providers.dart';

/// Staff and roles, mirroring the web's `/team`.
///
/// **Staff is the default tab, not Roles** — a deliberate difference from the
/// web. At a desk the job is usually "design the permission model"; on a phone
/// it is "the new waiter is standing here, approve them" or "she quit on
/// Friday". Roles stays one tap away.
///
/// The screen owns the single `_busy` flag and the one write helper. Two role
/// changes racing on the same member is exactly what that guards.
class TeamScreen extends ConsumerStatefulWidget {
  const TeamScreen({super.key});

  @override
  ConsumerState<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends ConsumerState<TeamScreen>
    with SingleTickerProviderStateMixin {
  /// Built in `initState`, not lazily: the no-access branch never reads it, and
  /// a `late final` would then be initialised *by* `dispose()` — constructing a
  /// controller against an element that is already going away.
  late final TabController _tabs;

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this)
      ..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canSee = ref.watch(canSeeTeamProvider);
    final canEdit = ref.watch(canEditTeamProvider);
    final theme = Theme.of(context);

    if (!canSee) {
      return const AppScaffold(title: 'Team', body: _NoTeamAccess());
    }

    return AppScaffold(
      title: 'Team',
      bottom: TabBar(
        controller: _tabs,
        tabs: const [
          Tab(text: 'Staff'),
          Tab(text: 'Roles'),
        ],
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          StaffTab(onAction: _memberAction, onJoinCode: _joinCode),
          RolesTab(onOpen: _openRole, onDelete: _deleteRole),
        ],
      ),
      floatingActionButton: canEdit && !_busy
          ? FloatingActionButton.extended(
              onPressed: _tabs.index == 0 ? _addMember : _newRole,
              icon: Icon(_tabs.index == 0 ? Icons.person_add_alt : Icons.add),
              label: Text(_tabs.index == 0 ? 'Add member' : 'Add role'),
            )
          : null,
      bottomNavigationBar: canEdit
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    Icon(
                      Icons.visibility_outlined,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'You can see the team but not change it.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  // --- staff ---------------------------------------------------------------

  Future<void> _addMember() async {
    final roles = ref.read(roleOptionsProvider);
    if (roles.isEmpty) {
      _say('No roles to assign yet. Add one on the Roles tab first.');
      return;
    }
    final draft = await showAddMemberSheet(context, roles: roles);
    if (draft == null) return;
    await _run((repo) async {
      final invited = await repo.addMember(
        email: draft.email,
        roleId: draft.roleId,
      );
      return invited
          ? "No account for ${draft.email} yet — invite saved. They'll join "
                'when they sign up.'
          : '${draft.email} added to the team.';
    });
  }

  Future<void> _memberAction(TeamMember member, MemberAction action) async {
    switch (action) {
      case MemberAction.changeRole:
        final roles = ref.read(roleOptionsProvider);
        final roleId = await showRolePickerSheet(
          context,
          roles: roles,
          email: member.email,
          currentRoleId: member.roleId,
        );
        if (roleId == null || roleId == member.roleId) return;
        await _run((repo) async {
          await repo.setMemberRole(userId: member.userId!, roleId: roleId);
          return 'Role updated.';
        });

      case MemberAction.approve:
        await _run((repo) async {
          await repo.approveMember(member.userId!);
          return '${member.email} approved.';
        });

      case MemberAction.remove:
        final ok = await _confirm(
          title: 'Remove ${member.email}?',
          body:
              'They lose access to this restaurant immediately. Their past '
              'orders and audit history stay put.',
          confirm: 'Remove',
        );
        if (!ok) return;
        await _run((repo) async {
          await repo.removeMember(member.userId!);
          return '${member.email} removed.';
        });

      case MemberAction.cancelInvite:
        final ok = await _confirm(
          title: 'Cancel this invite?',
          body:
              "${member.email} won't be able to join with this invite. You "
              'can invite them again later.',
          confirm: 'Cancel invite',
        );
        if (!ok) return;
        await _run((repo) async {
          await repo.cancelInvite(member.email);
          return 'Invite cancelled.';
        });
    }
  }

  Future<void> _joinCode() async {
    final choice = await showJoinCodeSheet(
      context,
      roles: ref.read(roleOptionsProvider),
    );
    if (choice == null) return;
    final roleId = choice == kDefaultJoinRole ? null : choice;

    String? code;
    await _run((repo) async {
      code = await repo.createJoinCode(roleId: roleId);
      return null;
    });
    final made = code;
    if (made == null || !mounted) return;
    await showJoinCodeResultDialog(context, code: made);
  }

  // --- roles ---------------------------------------------------------------

  Future<void> _newRole() => _pushEditor(null);

  Future<void> _openRole(TeamRole role) => _pushEditor(role);

  Future<void> _pushEditor(TeamRole? role) async {
    // The editor owns its own write, so it reports back with the message
    // rather than a draft. See its doc comment for why it is a screen.
    final message = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => RoleEditorScreen(role: role)),
    );
    if (message != null) _say(message);
  }

  Future<void> _deleteRole(TeamRole role) async {
    final ok = await _confirm(
      title: 'Delete the ${role.name} role?',
      body: _deleteRoleBody(role),
      confirm: 'Delete role',
    );
    if (!ok) return;
    await _run((repo) async {
      await repo.deleteRole(role);
      // A member's role_name just became null, so the roster is stale too.
      ref.invalidate(teamMembersProvider);
      return '${role.name} deleted.';
    });
  }

  String _deleteRoleBody(TeamRole role) {
    final fallback = role.baseRole;
    if (!role.countKnown) {
      return 'Anyone holding this role keeps their account but falls back to '
          "the default $fallback permissions. This can't be undone.";
    }
    if (role.memberCount == 0) {
      return "Nobody holds this role, so no one's access changes. This can't "
          'be undone.';
    }
    final who = role.memberCount == 1 ? 'person keeps' : 'people keep';
    return '${role.memberCount} $who their account but falls back to the '
        "default $fallback permissions. This can't be undone.";
  }

  // --- plumbing ------------------------------------------------------------

  /// One write, one busy flag, one place errors become something readable.
  Future<void> _run(Future<String?> Function(TeamRepository repo) write) async {
    final tenant = ref.read(activeTenantProvider);
    if (tenant == null || _busy) return;
    setState(() => _busy = true);
    try {
      final message = await write(
        ref.read(teamRepositoryProvider(tenant.tenantId)),
      );
      ref.invalidate(teamMembersProvider);
      ref.invalidate(teamRolesProvider);
      if (message != null) _say(message);
    } on Object catch (e) {
      _say('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String confirm,
  }) async {
    final theme = Theme.of(context);
    final answer = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirm),
          ),
        ],
      ),
    );
    return answer ?? false;
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(behavior: SnackBarBehavior.floating, content: Text(message)),
      );
  }
}

class _NoTeamAccess extends StatelessWidget {
  const _NoTeamAccess();

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
              Icons.lock_outline,
              size: 40,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'The team is not yours to see',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'Managing staff needs the View team permission. Ask an owner to '
              'grant it.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
