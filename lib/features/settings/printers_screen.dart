import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_scaffold.dart';
import '../../core/theme/tokens.dart';
import '../../data/print/print_models.dart';
import '../../data/print/print_providers.dart';
import '../../data/print/print_repository.dart';
import '../tenant/tenant_providers.dart';
import 'settings_providers.dart';

/// The printer registry, and what each printer is set to fire.
///
/// **Read-only, deliberately.** `save_printer` and `delete_printer` exist and
/// are gated on `settings.edit`, so the phone *could* write here — but a phone
/// cannot enumerate USB devices or system print queues the way the browser
/// agent does, so half the connection types could only ever be typed in blind.
/// An editor that can create a printer nothing is able to drive is worse than
/// a list that says where the editor lives.
///
/// A test page can still be sent from here: it goes through the same claim →
/// render → send path as a real ticket, so it proves the whole chain rather
/// than one socket.
class PrintersScreen extends ConsumerWidget {
  const PrintersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registry = ref.watch(printerRegistryProvider);
    final limit = ref.watch(printerLimitProvider).valueOrNull;
    final tenantId = ref.watch(activeTenantProvider)?.tenantId;

    return AppScaffold(
      title: 'Printers',
      showDrawer: false,
      subtitle: registry.valueOrNull == null
          ? null
          : limit == null
          ? '${registry.value!.length} set up'
          : '${registry.value!.length} of $limit',
      body: registry.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _Problem(
          message: '$e',
          onRetry: () => ref.invalidate(printerRegistryProvider),
        ),
        data: (rows) => RefreshIndicator(
          onRefresh: () async {
            ref
              ..invalidate(printerRegistryProvider)
              ..invalidate(printerLimitProvider);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            children: [
              if (rows.isEmpty)
                const _Empty()
              else
                for (final row in rows)
                  _PrinterCard(row: row, tenantId: tenantId),
              const SizedBox(height: 12),
              Text(
                'Printers are added and assigned on the web, in Settings → '
                'Printers. Assigning a document to a printer is what makes it '
                'fire on its own.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrinterCard extends ConsumerStatefulWidget {
  const _PrinterCard({required this.row, required this.tenantId});

  final PrinterRegistryRow row;
  final String? tenantId;

  @override
  ConsumerState<_PrinterCard> createState() => _PrinterCardState();
}

class _PrinterCardState extends ConsumerState<_PrinterCard> {
  bool _busy = false;

  Future<void> _test() async {
    final tenantId = widget.tenantId;
    if (tenantId == null || _busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(printRepositoryProvider(tenantId))
          .enqueueTest(widget.row.printer.id);
      if (!mounted) return;
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Test page queued for ${widget.row.printer.name}. It prints on '
              'whichever device is set up to drive it.',
            ),
          ),
        );
      ref.invalidate(printJobsProvider);
    } catch (e) {
      if (!mounted) return;
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final printer = widget.row.printer;
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final icon = switch (printer.connection) {
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
                    printer.name,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                // A word, not a colour — an inactive printer's documents fall
                // through to whichever other printer carries them.
                if (!printer.isActive)
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
              '${printerConnectionLabel(printer.connection)}  ·  '
              '${printer.target}  ·  ${printer.paperWidth}mm',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            if (widget.row.docs.isEmpty)
              Text(
                'Fires nothing on its own — pick it by hand to print to it.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: semantic.neutral,
                ),
              )
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final doc in widget.row.docs)
                    Chip(
                      label: Text(doc.label),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      labelStyle: theme.textTheme.labelSmall,
                    ),
                ],
              ),
            if (!printer.drivableHere)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'This phone cannot drive it — a computer prints this one.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: semantic.neutral,
                  ),
                ),
              ),
            if (printer.renderMode == PrinterRenderMode.image)
              Padding(
                padding: const EdgeInsets.only(top: 6),
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
            // waiter would only ever get a 42501 out of this button.
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

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
      child: Column(
        children: [
          const Icon(Icons.print_disabled_outlined, size: 36),
          const SizedBox(height: 12),
          Text(
            'No printers yet',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            'Add one on the web in Settings → Printers. For a WiFi printer you '
            'need its IP address; press its feed button while switching it on '
            'and it prints one.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
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
              "Couldn't load the printers.",
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
