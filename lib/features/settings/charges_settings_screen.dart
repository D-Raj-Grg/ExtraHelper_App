import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_scaffold.dart';
import '../../core/theme/tokens.dart';
import '../../data/supabase/pos_repository.dart' show PosFailure;
import '../../data/supabase/settings_repository.dart';
import '../pos/bill_providers.dart';
import '../tenant/tenant_providers.dart';
import 'charges_form.dart';
import 'settings_form.dart';
import 'settings_providers.dart';
import 'tax_rule_sheet.dart';

/// What gets added to a bill beyond the food.
///
/// Nothing here is computed on the phone. The screen describes the rules; every
/// total is worked out in Postgres, on both clients, from these same columns.
class ChargesSettingsScreen extends ConsumerStatefulWidget {
  const ChargesSettingsScreen({super.key});

  @override
  ConsumerState<ChargesSettingsScreen> createState() =>
      _ChargesSettingsScreenState();
}

class _ChargesSettingsScreenState extends ConsumerState<ChargesSettingsScreen> {
  final _service = TextEditingController();
  final _packaging = TextEditingController();

  TenantSettings? _loaded;
  List<TaxRuleDraft> _rules = const [];

  /// Only ever counts up. Reusing an index would hand a new rule the identity
  /// of a deleted one, and the row it replaced would keep that row's state.
  int _nextRuleId = 0;

  String? _serviceError;
  String? _packagingError;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onTyped);
    _packaging.addListener(_onTyped);
  }

  @override
  void dispose() {
    _service
      ..removeListener(_onTyped)
      ..dispose();
    _packaging
      ..removeListener(_onTyped)
      ..dispose();
    super.dispose();
  }

  void _onTyped() => setState(() {});

  void _seed(TenantSettings settings) {
    if (_loaded != null) return;
    _loaded = settings;
    _service.text = formatRate(settings.serviceCharge);
    _packaging.text = formatFee(settings.packagingFee);
    _rules = [
      for (final rule in settings.taxRules) TaxRuleDraft(_nextRuleId++, rule),
    ];
  }

  bool get _dirty {
    final loaded = _loaded;
    if (loaded == null) return false;
    if (_service.text.trim() != formatRate(loaded.serviceCharge)) return true;
    if (_packaging.text.trim() != formatFee(loaded.packagingFee)) return true;
    if (_rules.length != loaded.taxRules.length) return true;
    for (var i = 0; i < _rules.length; i++) {
      final a = _rules[i].rule;
      final b = loaded.taxRules[i];
      if (a.name != b.name || a.rate != b.rate || a.inclusive != b.inclusive) {
        return true;
      }
    }
    return false;
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

  Future<void> _save() async {
    final tenant = ref.read(activeTenantProvider);
    if (_loaded == null || tenant == null || _busy) return;

    final serviceError = validateServiceCharge(_service.text);
    final packagingError = validatePackagingFee(_packaging.text);
    if (serviceError != null || packagingError != null) {
      setState(() {
        _serviceError = serviceError;
        _packagingError = packagingError;
      });
      return;
    }

    setState(() {
      _serviceError = null;
      _packagingError = null;
      _busy = true;
    });

    final serviceCharge = double.parse(_service.text.trim());
    final packagingFee = double.parse(_packaging.text.trim());
    final rules = [for (final draft in _rules) draft.rule];

    String message;
    var saved = false;
    try {
      await ref
          .read(settingsRepositoryProvider(tenant.tenantId))
          .saveCharges(
            serviceCharge: serviceCharge,
            packagingFee: packagingFee,
            taxRules: rules,
          );
      saved = true;
      message = 'Charges saved.';
    } on PosFailure catch (e) {
      message = e.message;
    } finally {
      if (mounted) setState(() => _busy = false);
    }

    if (saved) {
      final loaded = _loaded!;
      _loaded = TenantSettings(
        currency: loaded.currency,
        timezone: loaded.timezone,
        dayCutoffMinutes: loaded.dayCutoffMinutes,
        serviceCharge: serviceCharge,
        packagingFee: packagingFee,
        taxRules: rules,
        receipt: loaded.receipt,
        blockNegativeStock: loaded.blockNegativeStock,
        qrAutoFire: loaded.qrAutoFire,
        paymentGateway: loaded.paymentGateway,
        printingMode: loaded.printingMode,
      );
      ref.invalidate(tenantSettingsProvider);
      // Charge lines on an open bill are recomputed server-side from these
      // columns, so any preview already on screen is now describing the old
      // rules.
      ref.invalidate(filteredBillsProvider);
    }

    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final tenant = ref.watch(activeTenantProvider);
    final canEdit = ref.watch(hasPermissionProvider('settings.edit'));
    final settings = ref.watch(tenantSettingsProvider);

    settings.whenData((value) {
      if (value != null) _seed(value);
    });

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || !mounted) return;
        final navigator = Navigator.of(context);
        if (await confirmDiscard(context)) navigator.pop();
      },
      child: AppScaffold(
        title: 'Charges & tax',
        showDrawer: false,
        bottomNavigationBar: _loaded == null
            ? null
            : SettingsSaveBar(
                canEdit: canEdit,
                dirty: _dirty,
                busy: _busy,
                onSave: _save,
              ),
        body: settings.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _Problem(
            message: '$e',
            onRetry: () => ref.invalidate(tenantSettingsProvider),
          ),
          data: (_) => ListView(
            padding: const EdgeInsets.only(top: 6, bottom: 24),
            children: [
              SettingsSection(
                title: 'Charges',
                children: [
                  TextField(
                    controller: _service,
                    enabled: canEdit,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Service charge',
                      suffixText: '%',
                      helperText: 'Added to every dine-in bill.',
                      border: const OutlineInputBorder(),
                      errorText: _serviceError,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _packaging,
                    enabled: canEdit,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Packaging fee',
                      // In whole currency units, unlike every other amount in
                      // this app — the column is `numeric(10,2)`, not cents.
                      prefixText: '${tenant?.currency ?? ''} ',
                      helperText: 'A flat fee on takeaway and delivery.',
                      border: const OutlineInputBorder(),
                      errorText: _packagingError,
                    ),
                  ),
                ],
              ),
              SettingsSection(
                title: 'Tax rules',
                detail:
                    'Exclusive rules are added on top of the subtotal and '
                    'service charge. Inclusive rules are already in the price.',
                children: [
                  if (_rules.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'No tax rules — prices are tax-free. Add VAT or GST '
                        'here.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  for (final draft in _rules)
                    // Keyed on the draft's own id, never on its contents: two
                    // rules can share a name mid-edit, and a content key moves
                    // the caret to whichever row now matches.
                    ListTile(
                      key: ValueKey(draft.id),
                      contentPadding: EdgeInsets.zero,
                      minTileHeight: Tokens.tapTarget,
                      title: Text(draft.rule.name),
                      subtitle: Text(describeTaxRule(draft.rule)),
                      trailing: canEdit
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Edit',
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () => _editRule(draft),
                                ),
                                IconButton(
                                  tooltip: 'Remove',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () => _removeRule(draft),
                                ),
                              ],
                            )
                          : null,
                    ),
                  if (canEdit) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _addRule,
                      icon: const Icon(Icons.add),
                      label: const Text('Add tax rule'),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Problem extends StatelessWidget {
  const _Problem({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 36),
            const SizedBox(height: 12),
            Text(
              "Couldn't load your settings.",
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
