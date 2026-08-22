import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_scaffold.dart';
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
    final printers = ref.watch(printersProvider);
    final jobs = ref.watch(printJobsProvider);
    final tenant = ref.watch(activeTenantProvider);

    return AppScaffold(
      title: 'Printing',
      body: RefreshIndicator(
        onRefresh: () async {
          ref
            ..invalidate(printersProvider)
            ..invalidate(printJobsProvider);
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

            Text('Printers', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Set up on the web, in Settings → Printers. Assigning a document '
              'there is what makes a printer fire on its own.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            printers.when(
              loading: () => const _Loading(),
              error: (e, _) => _Problem(
                message: "Couldn't load the printers.",
                detail: '$e',
                onRetry: () => ref.invalidate(printersProvider),
              ),
              data: (list) => list.isEmpty
                  ? const _Empty(
                      icon: Icons.print_disabled_outlined,
                      title: 'No printers yet',
                      body:
                          'Add one on the web in Settings → Printers. For a WiFi '
                          'printer you need its IP address; press its feed button '
                          'while switching it on and it prints one.',
                    )
                  : Column(
                      children: [
                        for (final p in list)
                          _PrinterTile(printer: p, tenantId: tenant?.tenantId),
                      ],
                    ),
            ),
            const SizedBox(height: 24),

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

class _PrinterTile extends ConsumerStatefulWidget {
  const _PrinterTile({required this.printer, required this.tenantId});

  final PrintPrinter printer;
  final String? tenantId;

  @override
  ConsumerState<_PrinterTile> createState() => _PrinterTileState();
}

class _PrinterTileState extends ConsumerState<_PrinterTile> {
  bool _busy = false;

  /// Queue a test page rather than printing it here directly.
  ///
  /// It goes through the same claim → render → send path as a real ticket, so a
  /// successful test proves the whole chain, not just that this phone can open
  /// a socket.
  Future<void> _test() async {
    final tenantId = widget.tenantId;
    if (tenantId == null) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(printRepositoryProvider(tenantId))
          .enqueueTest(widget.printer.id);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Test page queued for ${widget.printer.name}. '
            'It prints on whichever device is set up to drive it.',
          ),
        ),
      );
      ref.invalidate(printJobsProvider);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.printer;
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final icon = switch (p.connection) {
      PrinterConnection.network => Icons.wifi,
      PrinterConnection.bluetooth => Icons.bluetooth,
      PrinterConnection.usb => Icons.usb,
      PrinterConnection.system => Icons.print,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    p.name,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (!p.isActive)
                  Text(
                    'Off',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: semantic.neutral,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '${printerConnectionLabel(p.connection)}  ·  ${p.target}  ·  ${p.paperWidth}mm',
              style: theme.textTheme.bodySmall,
            ),
            if (!p.drivableHere)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'This phone cannot drive it — a computer prints this one.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: semantic.neutral,
                  ),
                ),
              ),
            if (p.renderMode == PrinterRenderMode.image)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Set to image mode, which needs a browser. This phone leaves '
                  'those tickets alone.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: semantic.infoText,
                  ),
                ),
              ),
            const SizedBox(height: 6),
            // `enqueue_print_job` gates a test page on `settings.edit`, so a
            // waiter would only ever get a 42501 out of this button. Say who
            // can, rather than offering a door that will not open.
            if (ref.watch(hasPermissionProvider('settings.edit')))
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _busy || widget.tenantId == null ? null : _test,
                  icon: const Icon(Icons.description_outlined),
                  label: Text(_busy ? 'Queueing…' : 'Test print'),
                ),
              )
            else
              Text(
                'An owner or manager can send a test page.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: semantic.neutral,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Printers this phone is paired with, so the address can be copied into the
/// web form rather than typed off the label with a digit wrong.
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

  static const _docLabels = {
    'kot': 'Kitchen ticket',
    'bot': 'Bar ticket',
    'full_kot': 'Full ticket',
    'order_slip': 'Order slip',
    'bill': 'Bill',
    'receipt': 'Receipt',
    'day_report': 'Day close (Z)',
    'test': 'Test page',
  };

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
                  '${_docLabels[job.doc] ?? job.doc} · $word',
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
