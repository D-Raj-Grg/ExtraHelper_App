import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/region_options.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/notice.dart';
import '../../data/supabase/auth_repository.dart';
import '../../data/supabase/tenant_repository.dart';
import '../settings/charges_form.dart';
import '../settings/tax_rule_sheet.dart';
import '../tenant/tenant_providers.dart';
import 'auth_validation.dart';

/// Where a signed-in user with no restaurant lands.
///
/// Two ways out, and the screen leads with the choice rather than assuming one:
/// **create** a restaurant, or **join** one someone else runs. It used to offer
/// only the join code, which left an owner who signed up on their phone with no
/// way forward at all and no explanation of why.
///
/// Steps are local state, not routes — same as the web's
/// `components/onboarding-form.tsx`. Backing out of "create" should return to
/// the choice, not leave the app.
enum _Step { start, create, join }

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  _Step _step = _Step.start;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(switch (_step) {
          _Step.start => 'Get started',
          _Step.create => 'New restaurant',
          _Step.join => 'Join a restaurant',
        }),
        leading: _step == _Step.start
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back',
                onPressed: () => setState(() => _step = _Step.start),
              ),
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
              child: switch (_step) {
                _Step.start => _StartStep(
                  onChoose: (step) => setState(() => _step = step),
                ),
                _Step.create => const _CreateStep(),
                _Step.join => const _JoinStep(),
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// The choice, plus who you are signed in as — someone who has just verified an
/// email deserves to see which one landed them here.
class _StartStep extends ConsumerWidget {
  const _StartStep({required this.onChoose});

  final void Function(_Step) onChoose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final email = ref.watch(authRepositoryProvider).currentUser?.email;
    final pending =
        ref.watch(pendingMembershipsProvider).valueOrNull ?? const [];

    return Column(
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
        if (email != null) ...[
          const SizedBox(height: 4),
          Text(
            email,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 24),
        _ChoiceCard(
          icon: Icons.storefront_outlined,
          title: 'Set up a restaurant',
          detail:
              'You run the place. Pick a currency and timezone and you can '
              'start taking orders.',
          onTap: () => onChoose(_Step.create),
        ),
        const SizedBox(height: 12),
        _ChoiceCard(
          icon: Icons.group_add_outlined,
          title: 'Join a restaurant',
          detail:
              'Someone gave you a join code, or invited you by email. An owner '
              'approves you, then you are in.',
          onTap: () => onChoose(_Step.join),
        ),
      ],
    );
  }
}

/// A big, unambiguous target. 44 is the floor everywhere in this app; a
/// decision this consequential gets more room than the floor.
class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(Tokens.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Tokens.radiusMd),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: theme.colorScheme.primary),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 4),
                    Text(
                      detail,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

/// Create the restaurant. Mirrors the web's create step field for field.
class _CreateStep extends ConsumerStatefulWidget {
  const _CreateStep();

  @override
  ConsumerState<_CreateStep> createState() => _CreateStepState();
}

class _CreateStepState extends ConsumerState<_CreateStep> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _service = TextEditingController();

  String _currency = kDefaultCurrency;
  String _timezone = kDefaultTimezone;
  List<TaxRuleDraft> _rules = const [];
  int _nextRuleId = 0;

  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // The name typed at signup was stashed in user metadata precisely so it
    // could be offered back here (`app/onboarding/page.tsx` does the same).
    final meta = ref.read(authRepositoryProvider).currentUser?.userMetadata;
    final stashed = (meta?['restaurant_name'] as String?)?.trim() ?? '';
    if (stashed.isNotEmpty) _name.text = stashed;
  }

  @override
  void dispose() {
    _name.dispose();
    _service.dispose();
    super.dispose();
  }

  Future<void> _addRule() async {
    final rule = await showTaxRuleSheet(context);
    if (rule == null) return;
    setState(() => _rules = [..._rules, TaxRuleDraft(_nextRuleId++, rule)]);
  }

  Future<void> _editRule(TaxRuleDraft draft) async {
    final rule = await showTaxRuleSheet(context, editing: draft.rule);
    if (rule == null) return;
    setState(() {
      _rules = [
        for (final existing in _rules)
          existing.id == draft.id ? existing.withRule(rule) : existing,
      ];
    });
  }

  void _removeRule(TaxRuleDraft draft) {
    setState(() {
      _rules = [
        for (final existing in _rules)
          if (existing.id != draft.id) existing,
      ];
    });
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final tenantId = await ref
          .read(tenantRepositoryProvider)
          .provisionTenant(
            name: _name.text,
            currency: _currency,
            timezone: _timezone,
            serviceCharge: parsePercent(_service.text),
            taxRules: [for (final draft in _rules) draft.rule],
          );
      // Select it before the memberships refetch, so the router lands on the
      // restaurant just created rather than whichever one sorts first.
      await ref.read(activeTenantSelectionProvider.notifier).select(tenantId);
      // `ref` is dead once this State is disposed, and there is an await above
      // it — the restaurant exists either way, so a torn-down screen must not
      // turn into a crash on the way out.
      if (!mounted) return;
      ref.invalidate(membershipsProvider);
      ref.invalidate(pendingMembershipsProvider);
      // The router takes it from here once memberships resolve non-empty.
    } on TenantFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Currency, timezone and tax can all be changed later in Settings.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),

          TextFormField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Restaurant name',
              hintText: 'Acme Diner',
            ),
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            enabled: !_busy,
            validator: (v) => (v ?? '').trim().isEmpty
                ? 'Restaurant name is required.'
                : null,
          ),
          const SizedBox(height: 14),

          DropdownButtonFormField<String>(
            initialValue: _currency,
            decoration: const InputDecoration(labelText: 'Currency'),
            items: [
              for (final c in kCurrencyOptions)
                DropdownMenuItem(value: c, child: Text(c)),
            ],
            onChanged: _busy
                ? null
                : (v) => setState(() => _currency = v ?? kDefaultCurrency),
          ),
          const SizedBox(height: 14),

          DropdownButtonFormField<String>(
            initialValue: _timezone,
            decoration: const InputDecoration(labelText: 'Timezone'),
            items: [
              for (final t in kTimezoneOptions)
                DropdownMenuItem(value: t, child: Text(t)),
            ],
            onChanged: _busy
                ? null
                : (v) => setState(() => _timezone = v ?? kDefaultTimezone),
          ),
          const SizedBox(height: 14),

          TextFormField(
            controller: _service,
            decoration: const InputDecoration(
              labelText: 'Service charge',
              suffixText: '%',
              helperText: 'Leave blank for none.',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: theme.textTheme.bodyLarge?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            enabled: !_busy,
            // Blank is a real answer here — most restaurants add nothing, and
            // making them type "0" is a worse form. Anything typed goes through
            // the settings screen's rule, so the two agree.
            validator: (v) => (v ?? '').trim().isEmpty
                ? null
                : validateServiceCharge(v ?? ''),
          ),

          const SizedBox(height: 24),
          _TaxRules(
            rules: _rules,
            busy: _busy,
            onAdd: _addRule,
            onEdit: _editRule,
            onRemove: _removeRule,
          ),

          if (_error != null) ...[
            const SizedBox(height: 16),
            ErrorNotice(message: _error!),
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
                : const Text('Create restaurant'),
          ),
        ],
      ),
    );
  }
}

class _TaxRules extends StatelessWidget {
  const _TaxRules({
    required this.rules,
    required this.busy,
    required this.onAdd,
    required this.onEdit,
    required this.onRemove,
  });

  final List<TaxRuleDraft> rules;
  final bool busy;
  final VoidCallback onAdd;
  final void Function(TaxRuleDraft) onEdit;
  final void Function(TaxRuleDraft) onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Tax', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          rules.isEmpty
              ? 'No tax rules yet. Add one if your bills carry VAT or GST.'
              : 'Applied to every bill.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        for (final draft in rules)
          // Keyed on the draft's id, never its contents: a key built from the
          // name changes on every keystroke and remounts the row.
          ListTile(
            key: ValueKey(draft.id),
            contentPadding: EdgeInsets.zero,
            title: Text(draft.rule.name),
            subtitle: Text(describeTaxRule(draft.rule)),
            onTap: busy ? null : () => onEdit(draft),
            trailing: IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Remove ${draft.rule.name}',
              onPressed: busy ? null : () => onRemove(draft),
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: busy ? null : onAdd,
          icon: const Icon(Icons.add),
          label: const Text('Add tax rule'),
        ),
      ],
    );
  }
}

/// Redeem a join code.
///
/// Lifted wholesale from the old `JoinCodeScreen`: redeeming creates a
/// *pending* membership an owner approves under Team, and the
/// screen says so, because "submitted and waiting" and "rejected" feel
/// identical otherwise.
class _JoinStep extends ConsumerStatefulWidget {
  const _JoinStep();

  @override
  ConsumerState<_JoinStep> createState() => _JoinStepState();
}

class _JoinStepState extends ConsumerState<_JoinStep> {
  final _code = TextEditingController();
  bool _busy = false;
  bool _refreshing = false;
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

  /// Pull in any invite sent to this address.
  ///
  /// Someone invited by email has nothing to type — before this the app had no
  /// way to attach that invite at all, and they were stuck asking for a code
  /// that was never going to be issued.
  Future<void> _refreshInvites() async {
    setState(() => _refreshing = true);
    await ref.read(authRepositoryProvider).claimInvites();
    // Signing out mid-request disposes this screen, and `ref` goes with it.
    if (!mounted) return;
    ref.invalidate(membershipsProvider);
    ref.invalidate(pendingMembershipsProvider);
    setState(() => _refreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pending =
        ref.watch(pendingMembershipsProvider).valueOrNull ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pending.isNotEmpty) ...[
          _PendingNotice(names: pending.map((p) => p.name).toList()),
          const SizedBox(height: 24),
        ],

        Text(
          'Ask your manager for a join code, then enter it here. They approve '
          'you afterwards and you get straight in.',
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
          ErrorNotice(message: _error!),
        ],
        if (_result != null) ...[
          const SizedBox(height: 16),
          AppNotice(
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
        const SizedBox(height: 8),
        TextButton(
          onPressed: _refreshing ? null : _refreshInvites,
          child: Text(
            _refreshing ? 'Checking…' : 'Invited by email? Check for invites',
          ),
        ),
      ],
    );
  }
}

class _PendingNotice extends StatelessWidget {
  const _PendingNotice({required this.names});

  final List<String> names;

  @override
  Widget build(BuildContext context) {
    final list = names.join(', ');
    return AppNotice(
      message: names.length == 1
          ? 'Waiting for $list to approve you. Tap "Check again" once they have.'
          : 'Waiting for approval from: $list.',
      icon: Icons.hourglass_top,
      color: context.semantic.warningText,
    );
  }
}
