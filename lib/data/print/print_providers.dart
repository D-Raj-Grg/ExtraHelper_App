import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/env.dart';
import '../../core/prefs.dart';
import '../../features/tenant/tenant_providers.dart';
import '../supabase/supabase_providers.dart';
import 'print_models.dart';
import 'print_repository.dart';
import 'print_service.dart';
import 'render_client.dart';
import 'transports/bluetooth_transport.dart';
import 'transports/network_transport.dart';
import 'transports/print_transport.dart';

/// Whether *this* device drives printers.
///
/// Per device, not per restaurant: a manager's phone and the counter's tablet
/// are on the same account, and only one of them is standing next to the
/// printer. Off by default — a phone that quietly claims tickets while its
/// owner is on the bus is the failure this avoids.
const _printEnabledKey = 'print_from_this_device';

class PrintEnabled extends Notifier<bool> {
  /// Whether the stored value has had its say. Without this, a tap made while
  /// SharedPreferences was still opening is silently undone the moment it
  /// resolves — the switch flicks back on its own and the phone stops printing.
  bool _settled = false;

  @override
  bool build() {
    ref.listen(sharedPreferencesProvider, (_, next) {
      final prefs = next.valueOrNull;
      if (prefs == null || _settled) return;
      _settled = true;
      state = prefs.getBool(_printEnabledKey) ?? false;
    }, fireImmediately: true);
    return false;
  }

  Future<void> set(bool value) async {
    // A deliberate tap outranks whatever is on disk.
    _settled = true;
    state = value;
    final prefs = await ref.read(sharedPreferencesProvider.future);
    await prefs.setBool(_printEnabledKey, value);
  }
}

final printEnabledProvider = NotifierProvider<PrintEnabled, bool>(
  PrintEnabled.new,
);

final _printRepoProvider = Provider<PrintRepository?>((ref) {
  final tenant = ref.watch(activeTenantProvider);
  if (tenant == null) return null;
  return ref.watch(printRepositoryProvider(tenant.tenantId));
});

/// Printers as the registry holds them. Read-only here — they are set up on the
/// web, where there is room for the whole form.
final printersProvider = FutureProvider<List<PrintPrinter>>((ref) async {
  final repo = ref.watch(_printRepoProvider);
  if (repo == null) return const [];
  return repo.printers();
});

/// The tail of the queue, for the printing screen.
final printJobsProvider = FutureProvider<List<PrintJob>>((ref) async {
  final repo = ref.watch(_printRepoProvider);
  if (repo == null) return const [];
  return repo.jobs();
});

final networkTransportProvider = Provider<NetworkPrintTransport>(
  (ref) => const NetworkPrintTransport(),
);

final bluetoothTransportProvider = Provider<BluetoothPrintTransport>((ref) {
  final transport = BluetoothPrintTransport();
  ref.onDispose(() => unawaited(transport.dispose()));
  return transport;
});

/// What this device could print with, in the order the service should prefer.
final printTransportsProvider = Provider<List<PrintTransport>>((ref) {
  return [
    ref.watch(networkTransportProvider),
    ref.watch(bluetoothTransportProvider),
  ];
});

/// A name for `print_jobs.claimed_by`, so "which device printed this?" has an
/// answer a manager can act on.
final printClaimerProvider = Provider<String>((ref) {
  final email = ref.watch(currentUserProvider)?.email;
  final platform = Platform.isIOS ? 'iOS' : 'Android';
  return '$platform · ${email ?? 'app'}';
});

/// Null until a tenant resolves, the device is switched on for printing, and the
/// build knows where the web app lives.
final printServiceProvider = Provider<PrintService?>((ref) {
  if (!ref.watch(printEnabledProvider)) return null;
  if (!Env.canPrint) return null;
  final tenant = ref.watch(activeTenantProvider);
  final repo = ref.watch(_printRepoProvider);
  if (tenant == null || repo == null) return null;

  // What the restaurant actually owns decides which transports are consulted at
  // all. Until the registry answers, network alone — see `PrintService.configured`.
  final registry = ref.watch(printersProvider).valueOrNull;
  final configured = registry == null
      ? const {PrinterConnection.network}
      : {
          PrinterConnection.network,
          for (final p in registry)
            if (p.isActive) p.connection,
        };

  return PrintService(
    repository: repo,
    renderClient: RenderClient(ref.watch(supabaseProvider), tenant.tenantId),
    transports: ref.watch(printTransportsProvider),
    claimer: ref.watch(printClaimerProvider),
    configured: configured,
  );
});

/// Keeps the queue moving while the app is open.
///
/// Realtime is the fast path and the timer is the guarantee — a dropped socket,
/// or a job re-queued after a stale claim, would otherwise sit there until
/// somebody noticed the kitchen had gone quiet. Mounted once, next to
/// `SyncLoop`, for the same reason: one drainer per app, not one per screen.
class PrintLoop extends ConsumerStatefulWidget {
  const PrintLoop({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<PrintLoop> createState() => _PrintLoopState();
}

class _PrintLoopState extends ConsumerState<PrintLoop>
    with WidgetsBindingObserver {
  Timer? _ticker;
  RealtimeChannel? _channel;
  String? _subscribedTenant;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = Timer.periodic(const Duration(seconds: 20), (_) => _drain());
    WidgetsBinding.instance.addPostFrameCallback((_) => _drain());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _unsubscribe();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // The registry is read once and cached, so a printer added on the web while
    // this app sat in the background would otherwise stay invisible — and with
    // it, whether Bluetooth is worth consulting at all. Re-reading on resume is
    // the cheapest honest moment.
    ref.invalidate(printersProvider);
    // Coming back is also when a waiter expects the backlog to clear; iOS will
    // have suspended the socket while the app was away.
    _drain();
  }

  Future<void> _drain() async {
    final service = ref.read(printServiceProvider);
    if (service == null || service.isDraining) return;
    final printed = await service.drain();
    if (!mounted) return;
    if (printed > 0) ref.invalidate(printJobsProvider);
  }

  void _subscribe(String tenantId) {
    if (_subscribedTenant == tenantId) return;
    _unsubscribe();

    final client = ref.read(supabaseProvider);
    // Without the token RLS drops every event and the board merely looks "not
    // live" — the same trap the KDS board documents.
    final token = client.auth.currentSession?.accessToken;
    if (token != null) client.realtime.setAuth(token);

    _channel = client
        .channel('print_jobs_$tenantId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'print_jobs',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'tenant_id',
            value: tenantId,
          ),
          callback: (_) => _drain(),
        )
        .subscribe();
    _subscribedTenant = tenantId;
  }

  void _unsubscribe() {
    final channel = _channel;
    _channel = null;
    _subscribedTenant = null;
    if (channel != null) unawaited(channel.unsubscribe());
  }

  @override
  Widget build(BuildContext context) {
    // A token refresh leaves the socket authed with the *old* JWT, and RLS then
    // drops every event silently — the queue would only move on the 20s poll.
    // Re-subscribing carries the new token.
    ref.listen(authStateProvider, (_, _) {
      final tenant = _subscribedTenant;
      if (tenant == null) return;
      _unsubscribe();
      _subscribe(tenant);
    });

    final service = ref.watch(printServiceProvider);
    final want = service == null
        ? null
        : ref.watch(activeTenantProvider)?.tenantId;

    if (want != _subscribedTenant) {
      // Subscribing is a side effect on an external system, so it happens after
      // the frame rather than during it.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (want == null) {
          _unsubscribe();
        } else {
          _subscribe(want);
          // Switched on, or switched restaurant: clear whatever is waiting
          // rather than idling until the next tick.
          _drain();
        }
      });
    }

    return widget.child;
  }
}
