import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_scaffold.dart';
import '../../core/widgets/choice_chip.dart';
import '../../data/supabase/pos_repository.dart' show PosFailure;
import '../../data/supabase/settings_repository.dart';
import '../pos/bill_providers.dart';
import '../pos/pos_providers.dart';
import '../reports/day_report_providers.dart';
import '../tenant/tenant_providers.dart';
import 'settings_form.dart';
import 'settings_providers.dart';

/// Who this restaurant is, and the two switches that change how orders behave.
///
/// The web fuses this with charges and receipt text into one form. Split here
/// because the day cutoff on this screen is retroactive and needs its own
/// confirmation, and a confirmation that also commits tax rules someone edited
/// two screens ago is a confirmation nobody can read honestly.
class GeneralSettingsScreen extends ConsumerStatefulWidget {
  const GeneralSettingsScreen({super.key});

  @override
  ConsumerState<GeneralSettingsScreen> createState() =>
      _GeneralSettingsScreenState();
}

class _GeneralSettingsScreenState extends ConsumerState<GeneralSettingsScreen> {
  final _name = TextEditingController();

  TenantSettings? _loaded;
  String _loadedName = '';
  late String _currency;
  late String _timezone;
  late int _cutoff;
  late String _gateway;
  late bool _qrAutoFire;
  late bool _blockNegativeStock;

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _currency = 'USD';
    _timezone = 'UTC';
    _cutoff = 0;
    _gateway = 'sandbox';
    _qrAutoFire = true;
    _blockNegativeStock = false;
    _name.addListener(_onTyped);
  }

  @override
  void dispose() {
    _name
      ..removeListener(_onTyped)
      ..dispose();
    super.dispose();
  }

  void _onTyped() => setState(() {});

  /// Seeded **once**, from the first value that arrives. Re-seeding on every
  /// rebuild would throw away whatever is half-typed the moment anything else
  /// on the screen moves.
  void _seed(TenantSettings settings, String tenantName) {
    if (_loaded != null) return;
    _loaded = settings;
    _loadedName = tenantName;
    _name.text = tenantName;
    _currency = settings.currency;
    _timezone = settings.timezone;
    _cutoff = settings.dayCutoffMinutes;
    _gateway = settings.paymentGateway;
    _qrAutoFire = settings.qrAutoFire;
    _blockNegativeStock = settings.blockNegativeStock;
  }

  bool get _dirty {
    final loaded = _loaded;
    if (loaded == null) return false;
    return _name.text.trim() != _loadedName ||
        _currency != loaded.currency ||
        _timezone != loaded.timezone ||
        _cutoff != loaded.dayCutoffMinutes ||
        _gateway != loaded.paymentGateway ||
        _qrAutoFire != loaded.qrAutoFire ||
        _blockNegativeStock != loaded.blockNegativeStock;
  }

  Future<void> _save() async {
    final loaded = _loaded;
    final tenant = ref.read(activeTenantProvider);
    if (loaded == null || tenant == null || _busy) return;

    final cutoffMoved = _cutoff != loaded.dayCutoffMinutes;
    if (cutoffMoved && !await _confirmCutoff()) return;
    if (!mounted) return;

    setState(() => _busy = true);
    final repo = ref.read(settingsRepositoryProvider(tenant.tenantId));
    final wantsRename = _name.text.trim() != _loadedName;
    String message;
    var saved = false;
    try {
      await repo.saveGeneral(
        currency: _currency,
        timezone: _timezone,
        dayCutoffMinutes: _cutoff,
        paymentGateway: _gateway,
        qrAutoFire: _qrAutoFire,
        blockNegativeStock: _blockNegativeStock,
      );
      saved = true;
      message = 'Settings saved.';

      // A separate call, after the one above, because `tenants` is owner-only
      // while `tenant_settings` is owner-or-manager. Fused, a manager's rename
      // would take the settings down with it — or worse, appear to succeed.
      if (wantsRename) {
        try {
          await repo.renameTenant(_name.text.trim());
          _loadedName = _name.text.trim();
        } on PosFailure catch (e) {
          _name.text = _loadedName;
          message = 'Settings saved. ${e.message}';
        }
      }
    } on PosFailure catch (e) {
      message = e.message;
    } finally {
      if (mounted) setState(() => _busy = false);
    }

    if (saved) {
      _loaded = TenantSettings(
        currency: _currency,
        timezone: _timezone,
        dayCutoffMinutes: _cutoff,
        serviceCharge: loaded.serviceCharge,
        packagingFee: loaded.packagingFee,
        taxRules: loaded.taxRules,
        receipt: loaded.receipt,
        blockNegativeStock: _blockNegativeStock,
        qrAutoFire: _qrAutoFire,
        paymentGateway: _gateway,
        printingMode: loaded.printingMode,
      );
      ref.invalidate(tenantSettingsProvider);
      // Carries the name, currency and timezone the whole app formats against,
      // and re-stamps the Drift identity cache. Without this the till keeps
      // pricing in the old currency until it is restarted.
      ref.invalidate(membershipsProvider);
      if (cutoffMoved) {
        // Everything downstream of `tenant_day_start` just changed its answer.
        ref.invalidate(dayReportProvider);
        ref.invalidate(completedOrdersProvider);
        ref.invalidate(filteredBillsProvider);
      }
    }

    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _confirmCutoff() async {
    final label = dayCutoffOptions[_cutoff] ?? '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Start the day at $label?'),
        content: const Text(dayCutoffRetroWarning),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Change it'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  @override
  Widget build(BuildContext context) {
    final tenant = ref.watch(activeTenantProvider);
    final canEdit = ref.watch(hasPermissionProvider('settings.edit'));
    final isOwner = tenant?.role == 'owner';
    final settings = ref.watch(tenantSettingsProvider);

    settings.whenData((value) {
      if (value != null) _seed(value, tenant?.name ?? '');
    });

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || !mounted) return;
        // The navigator is captured before the await: `context` after one is
        // the lint's whole complaint, and a State's `mounted` says nothing
        // about whether this particular context is still mounted.
        final navigator = Navigator.of(context);
        if (await confirmDiscard(context)) navigator.pop();
      },
      child: AppScaffold(
        title: 'General',
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
                title: 'Restaurant',
                children: [
                  const FieldLabel('Name'),
                  TextField(
                    controller: _name,
                    // Owner-only at the RLS level. Disabled rather than
                    // silently refused, so a manager finds out before typing a
                    // new name rather than after.
                    enabled: canEdit && isOwner,
                    maxLength: 80,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      counterText: '',
                      helperText: isOwner
                          ? null
                          : 'Only the owner can rename the restaurant.',
                      helperMaxLines: 2,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const FieldLabel(
                    'Currency',
                    detail: 'Every price and total is shown in this.',
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final code in settingsCurrencies)
                        AppChoiceChip(
                          label: code,
                          selected: code == _currency,
                          showCheck: true,
                          enabled: canEdit,
                          onSelect: () => setState(() => _currency = code),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const FieldLabel(
                    'Timezone',
                    detail: 'Decides what "today" means on every report.',
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: settingsTimezones.contains(_timezone)
                        ? _timezone
                        : null,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                    // A zone the web set that is not in the short list still
                    // shows as the hint rather than silently reading as UTC.
                    hint: Text(_timezone),
                    items: [
                      for (final zone in settingsTimezones)
                        DropdownMenuItem(value: zone, child: Text(zone)),
                    ],
                    onChanged: canEdit
                        ? (value) => setState(() => _timezone = value ?? _timezone)
                        : null,
                  ),
                  const SizedBox(height: 16),
                  const FieldLabel(
                    'Day starts at',
                    detail:
                        'A sale at 1:30 am counts towards the night before when '
                        'the day starts later than midnight.',
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final entry in dayCutoffOptions.entries)
                        AppChoiceChip(
                          label: entry.value,
                          selected: entry.key == _cutoff,
                          showCheck: true,
                          enabled: canEdit,
                          onSelect: () => setState(() => _cutoff = entry.key),
                        ),
                    ],
                  ),
                ],
              ),
              SettingsSection(
                title: 'Payments',
                detail: 'How guests pay when they pay through the app.',
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final entry in paymentGateways.entries)
                        AppChoiceChip(
                          label: entry.value,
                          selected: entry.key == _gateway,
                          showCheck: true,
                          enabled: canEdit,
                          onSelect: () => setState(() => _gateway = entry.key),
                        ),
                    ],
                  ),
                ],
              ),
              SettingsSection(
                title: 'Operations',
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _qrAutoFire,
                    onChanged: canEdit
                        ? (value) => setState(() => _qrAutoFire = value)
                        : null,
                    title: const Text('Send QR orders straight to the kitchen'),
                    subtitle: const Text(
                      'Off means a waiter accepts each guest order first.',
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _blockNegativeStock,
                    onChanged: canEdit
                        ? (value) =>
                              setState(() => _blockNegativeStock = value)
                        : null,
                    title: const Text('Block sales below zero stock'),
                    subtitle: const Text(
                      'Firing an item that would take an ingredient negative '
                      'is refused, and the whole ticket rolls back.',
                    ),
                  ),
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
