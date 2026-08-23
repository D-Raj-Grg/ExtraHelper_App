import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_scaffold.dart';
import '../../app/router.dart';
import '../../core/env.dart';
import '../../core/theme/tokens.dart';
import '../../data/print/print_models.dart';
import '../../data/print/print_providers.dart';
import '../../data/print/print_repository.dart';
import '../../data/print/transports/bluetooth_transport.dart';
import '../tenant/tenant_providers.dart';

/// Printing, from this phone.
///
/// The registry itself is edited on the web, where there is room for the whole
/// form. What belongs *here* is everything that is true of this device and
/// nowhere else: whether it drives printers at all, which Bluetooth printers it
/// has been paired with, and whether the ticket actually came out.
class PrintingScreen extends ConsumerWidget {
  const PrintingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final enabled = ref.watch(printEnabledProvider);
    final jobs = ref.watch(printJobsProvider);

    return AppScaffold(
      title: 'Printing',
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(printJobsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            if (!Env.canPrint) const _NoAppUrlNotice(),

            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: enabled,
              onChanged: Env.canPrint
                  ? (v) => ref.read(printEnabledProvider.notifier).set(v)
                  : null,
              title: const Text('Print from this device'),
              subtitle: Text(
                enabled
                    ? 'This phone takes tickets off the queue and prints them. '
                          'Several devices can do this at once — a ticket is '
                          'claimed before it is sent, so it can never print twice.'
                    : 'Off. Tickets are left for the till, the shop computer, '
                          'or another phone.',
              ),
            ),
            const Divider(height: 24),

            Text(
              'What this phone can drive',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const _CapabilityRows(),
            const SizedBox(height: 24),

            // The registry itself lives in Settings → Printers. This screen is
            // about *this phone*; which printers exist is a property of the
            // restaurant, and mixing the two made one screen answer two
            // questions badly.
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.print_outlined),
              title: const Text('Printers'),
              subtitle: const Text(
                'See the registry and send a test page.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(Routes.settingsPrinters),
            ),
            const SizedBox(height: 16),

            const _PairedBluetooth(),
            const SizedBox(height: 24),

            Row(
              children: [
                Expanded(
                  child: Text(
                    'Recent tickets',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: () => ref.invalidate(printJobsProvider),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 4),
            jobs.when(
              loading: () => const _Loading(),
              error: (e, _) => _Problem(
                message: "Couldn't load the print queue.",
                detail: '$e',
                onRetry: () => ref.invalidate(printJobsProvider),
              ),
              data: (list) => list.isEmpty
                  ? const _Empty(
                      icon: Icons.receipt_long_outlined,
                      title: 'Nothing has printed yet',
                      body:
                          'Tickets appear here as soon as an order is fired or a '
                          'bill is settled.',
                    )
                  : Column(children: [for (final j in list) _JobTile(job: j)]),
            ),
          ],
        ),
      ),
    );
  }
}

/// Says why the switch is dead, next to the switch, rather than in a toast that
/// has gone by the time anyone wonders.
class _NoAppUrlNotice extends StatelessWidget {
  const _NoAppUrlNotice();

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: semantic.warning.withValues(alpha: 0.12),
        border: Border.all(color: semantic.warning),
        borderRadius: BorderRadius.circular(Tokens.radiusMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: semantic.warningText),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'This build was made without APP_URL, so it cannot build tickets. '
              'Rebuild the app with APP_URL set to your ExtraHelper web address.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

/// WiFi always; Bluetooth only when the OS says so. Each row carries an icon
/// and a word as well as a colour — the greyscale rule.
class _CapabilityRows extends ConsumerStatefulWidget {
  const _CapabilityRows();

  @override
  ConsumerState<_CapabilityRows> createState() => _CapabilityRowsState();
}

class _CapabilityRowsState extends ConsumerState<_CapabilityRows> {
  bool? _bluetooth;
  bool _permanentlyDenied = false;
  bool _asking = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final transport = ref.read(bluetoothTransportProvider);
    final ready = await transport.available;
    final denied = ready ? false : await transport.permanentlyDenied;
    if (!mounted) return;
    setState(() {
      _bluetooth = ready;
      _permanentlyDenied = denied;
    });
  }

  /// The permission is asked for here and nowhere else. The plugin never asks
  /// on its own — its request code is commented out — and a dialog that appears
  /// by itself mid-service is worse than no Bluetooth at all.
  Future<void> _ask() async {
    setState(() => _asking = true);
    await ref.read(bluetoothTransportProvider).requestPermission();
    if (!mounted) return;
    setState(() => _asking = false);
    await _check();
  }

  @override
  Widget build(BuildContext context) {
    final bt = _bluetooth;
    final supported = BluetoothPrintTransport.supportedPlatform;

    return Column(
      children: [
        const _CapabilityRow(
          icon: Icons.wifi,
          label: 'WiFi printers',
          ready: true,
          detail: 'Any printer on this network, on port 9100.',
        ),
        _CapabilityRow(
          icon: Icons.bluetooth,
          label: 'Bluetooth printers',
          ready: supported ? bt : false,
          detail: !supported
              ? 'An iPhone cannot drive a thermal printer over Bluetooth — '
                    'Apple requires a licensing chip these printers do not have. '
                    'Use WiFi, or an Android phone.'
              : bt == false
              ? _permanentlyDenied
                    ? 'Nearby devices permission was refused. Turn it on in the '
                          "phone's app settings, then pull down to refresh."
                    : 'Bluetooth is off, or the app has not been allowed to use '
                          'it yet.'
              : 'Printers this phone has been paired with.',
        ),
        // Only where it can actually change something: not on iPhone, and not
        // once the answer is a permanent no.
        if (supported && bt == false && !_permanentlyDenied)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 32, bottom: 4),
              child: OutlinedButton.icon(
                onPressed: _asking ? null : _ask,
                icon: const Icon(Icons.bluetooth_searching),
                label: Text(_asking ? 'Asking…' : 'Allow Bluetooth'),
              ),
            ),
          ),
        const _CapabilityRow(
          icon: Icons.usb,
          label: 'USB printers',
          ready: false,
          detail:
              'A phone cannot drive one. Leave those to a computer running QZ '
              'Tray, or the shop print agent.',
        ),
      ],
    );
  }
}

class _CapabilityRow extends StatelessWidget {
  const _CapabilityRow({
    required this.icon,
    required this.label,
    required this.ready,
    required this.detail,
  });

  final IconData icon;
  final String label;

  /// Null while it is still being asked.
  final bool? ready;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    final theme = Theme.of(context);
    final (mark, colour, word) = switch (ready) {
      true => (Icons.check_circle, semantic.goodText, 'Ready'),
      false => (Icons.remove_circle_outline, semantic.neutral, 'Not available'),
      _ => (Icons.more_horiz, semantic.neutral, 'Checking'),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(label, style: theme.textTheme.bodyLarge),
                    const SizedBox(width: 8),
                    Icon(mark, size: 16, color: colour),
                    const SizedBox(width: 4),
                    Text(
                      word,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colour,
                      ),
                    ),
                  ],
                ),
                Text(detail, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Printers this phone is paired with, so the address can be copied into the
/// printer form rather than typed off the label with a digit wrong.
class _PairedBluetooth extends ConsumerStatefulWidget {
  const _PairedBluetooth();

  @override
  ConsumerState<_PairedBluetooth> createState() => _PairedBluetoothState();
}

class _PairedBluetoothState extends ConsumerState<_PairedBluetooth> {
  List<({String name, String address})>? _devices;
  bool _scanning = false;

  Future<void> _scan() async {
    setState(() => _scanning = true);
    final BluetoothPrintTransport transport = ref.read(
      bluetoothTransportProvider,
    );
    final found = await transport.pairedPrinters();
    if (!mounted) return;
    setState(() {
      _devices = found;
      _scanning = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final devices = _devices;

    // On iPhone the plugin lists *nearby BLE* devices with CoreBluetooth UUIDs,
    // not paired printers with MAC addresses — an address copied from here
    // would not work on any other phone. Offering the list would be a lie.
    if (!BluetoothPrintTransport.supportedPlatform) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Paired Bluetooth printers', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Pair the printer in this phone\'s Bluetooth settings first. Then copy '
          'its address into Settings → Printers on the web, as a Bluetooth '
          'printer.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        if (devices == null)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _scanning ? null : _scan,
              icon: const Icon(Icons.bluetooth_searching),
              label: Text(_scanning ? 'Looking…' : 'Show paired printers'),
            ),
          )
        else if (devices.isEmpty)
          const _Empty(
            icon: Icons.bluetooth_disabled,
            title: 'Nothing paired',
            body:
                'Pair the printer in the phone\'s Bluetooth settings, then come '
                'back and look again.',
          )
        else
          Column(
            children: [
              for (final d in devices)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  minTileHeight: Tokens.tapTarget,
                  leading: const Icon(Icons.print_outlined),
                  title: Text(d.name.isEmpty ? 'Unnamed printer' : d.name),
                  subtitle: Text(
                    d.address,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  trailing: IconButton(
                    tooltip: 'Copy address',
                    icon: const Icon(Icons.copy),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: d.address));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Copied ${d.address}')),
                      );
                    },
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _scanning ? null : _scan,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Look again'),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _JobTile extends ConsumerWidget {
  const _JobTile({required this.job});

  final PrintJob job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final tenantId = ref.watch(activeTenantProvider)?.tenantId;

    // Icon and word carry the state; colour only reinforces it.
    final (icon, colour, word) = switch (job.status) {
      'printed' => (Icons.check_circle, semantic.goodText, 'Printed'),
      'failed' => (Icons.error_outline, semantic.dangerText, 'Failed'),
      'claimed' => (Icons.hourglass_top, semantic.infoText, 'Printing'),
      'cancelled' => (Icons.block, semantic.neutral, 'Cancelled'),
      _ => (Icons.schedule, semantic.warningText, 'Waiting'),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: colour),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${printDocLabel(job.doc)} · $word',
                  style: theme.textTheme.bodyMedium,
                ),
                Text(
                  [
                    if (job.printerName != null) job.printerName!,
                    _clock(job.createdAt),
                    if (job.claimedBy != null) job.claimedBy!,
                  ].join('  ·  '),
                  style: theme.textTheme.bodySmall,
                ),
                if (job.error != null)
                  Text(
                    job.error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: semantic.dangerText,
                    ),
                  ),
              ],
            ),
          ),
          if (job.status == 'failed' && tenantId != null)
            TextButton(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                try {
                  await ref
                      .read(printRepositoryProvider(tenantId))
                      .retry(job.id);
                  ref.invalidate(printJobsProvider);
                } catch (e) {
                  messenger.showSnackBar(SnackBar(content: Text('$e')));
                }
              },
              child: const Text('Retry'),
            ),
        ],
      ),
    );
  }

  static String _clock(DateTime at) {
    final h = at.hour.toString().padLeft(2, '0');
    final m = at.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 24),
    child: Center(child: CircularProgressIndicator()),
  );
}

/// Empty states teach the next step rather than saying "No data".
class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(Tokens.radiusMd),
      ),
      child: Column(
        children: [
          Icon(icon, size: 28, color: context.semantic.neutral),
          const SizedBox(height: 8),
          Text(title, style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            body,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _Problem extends StatelessWidget {
  const _Problem({
    required this.message,
    required this.detail,
    required this.onRetry,
  });

  final String message;
  final String detail;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.error.withValues(alpha: 0.1),
        border: Border.all(color: scheme.error, width: 1.5),
        borderRadius: BorderRadius.circular(Tokens.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline, size: 20, color: scheme.error),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: scheme.error),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(detail, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}
