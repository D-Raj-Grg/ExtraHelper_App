import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../data/supabase/auth_repository.dart';
import '../../data/supabase/tenant_repository.dart';
import '../tenant/tenant_providers.dart';

/// Where a signed-in user with no restaurant lands.
///
/// This is an **empty state that teaches the next step** rather than saying "no
/// access": redeeming a code creates a *pending* membership, which an owner
/// then approves on the web `/team` page. The screen says so, because
/// "submitted and waiting" and "rejected" feel identical otherwise.
class JoinCodeScreen extends ConsumerStatefulWidget {
  const JoinCodeScreen({super.key});

  @override
  ConsumerState<JoinCodeScreen> createState() => _JoinCodeScreenState();
}

class _JoinCodeScreenState extends ConsumerState<JoinCodeScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;
  JoinResult? _result;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await ref
          .read(tenantRepositoryProvider)
          .redeemJoinCode(_code.text);
      if (!mounted) return;
      setState(() => _result = result);
      // A code for a restaurant the user is already active in should let them
      // straight in, so refresh rather than leaving them on this screen.
      ref.invalidate(membershipsProvider);
      ref.invalidate(pendingMembershipsProvider);
    } on TenantFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pending =
        ref.watch(pendingMembershipsProvider).valueOrNull ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Join a restaurant'),
        actions: [
          TextButton(
            onPressed: () => ref.read(authRepositoryProvider).signOut(),
            child: const Text('Sign out'),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (pending.isNotEmpty) ...[
                    _PendingNotice(names: pending.map((p) => p.name).toList()),
                    const SizedBox(height: 24),
                  ],

                  Text(
                    "You're signed in, but not in a restaurant yet.",
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Ask your manager for a join code, then enter it here. '
                    'They approve you afterwards and you get straight in.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),

                  TextField(
                    controller: _code,
                    decoration: const InputDecoration(
                      labelText: 'Join code',
                      hintText: 'e.g. 7GQ4KD',
                    ),
                    textCapitalization: TextCapitalization.characters,
                    autocorrect: false,
                    enabled: !_busy,
                    onSubmitted: (_) => _submit(),
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    _Notice(
                      message: _error!,
                      icon: Icons.error_outline,
                      color: theme.colorScheme.error,
                    ),
                  ],
                  if (_result != null) ...[
                    const SizedBox(height: 16),
                    _Notice(
                      message: _result!.alreadyMember
                          ? "You're already on ${_result!.tenantName}'s team "
                                '(${_result!.status}).'
                          : 'Request sent to ${_result!.tenantName}. An owner or '
                                'manager approves it, then you can start taking orders.',
                      icon: Icons.check_circle_outline,
                      color: context.semantic.goodText,
                    ),
                  ],

                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Join'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () {
                      ref.invalidate(membershipsProvider);
                      ref.invalidate(pendingMembershipsProvider);
                    },
                    child: const Text('Check again'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PendingNotice extends StatelessWidget {
  const _PendingNotice({required this.names});

  final List<String> names;

  @override
  Widget build(BuildContext context) {
    final list = names.join(', ');
    return _Notice(
      message: names.length == 1
          ? 'Waiting for $list to approve you. Tap "Check again" once they have.'
          : 'Waiting for approval from: $list.',
      icon: Icons.hourglass_top,
      color: context.semantic.warningText,
    );
  }
}

/// Icon + colour + words. Never colour alone.
class _Notice extends StatelessWidget {
  const _Notice({
    required this.message,
    required this.icon,
    required this.color,
  });

  final String message;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color, width: 1.5),
        borderRadius: BorderRadius.circular(Tokens.radiusMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
