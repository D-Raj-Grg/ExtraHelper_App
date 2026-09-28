import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router.dart';
import '../../data/notifications/local_notifier.dart';
import '../tenant/tenant_providers.dart';
import 'notifications_providers.dart';

/// The third loop beside `SyncLoop` and `PrintLoop`: keeps the order feed —
/// and so the Realtime channel that raises OS alerts — alive whichever screen
/// is open, asks for the OS permission once, and routes a tap on a banner.
///
/// Mounted above the router, so it has no `Navigator` of its own. Anything it
/// shows goes through the router's navigator key.
///
/// When the app is killed nothing here runs and nothing arrives. Push through
/// FCM/APNs is phase 2; see `LocalNotifier`.
class NotifyLoop extends ConsumerStatefulWidget {
  const NotifyLoop({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<NotifyLoop> createState() => _NotifyLoopState();
}

class _NotifyLoopState extends ConsumerState<NotifyLoop>
    with WidgetsBindingObserver {
  StreamSubscription<String?>? _taps;

  /// A banner tapped before the shell could take it — a cold start from the
  /// tray, or a tap while memberships were still loading.
  bool _openPending = false;

  /// One pre-prompt per run at most, even if identity flaps.
  bool _promptChecked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final notifier = ref.read(localNotifierProvider);
    _openPending = notifier.launchedFromNotification;
    _taps = notifier.taps.listen((_) {
      _openPending = true;
      _maybeOpenFeed();
    });
    // Manual rather than in build(), for `fireImmediately`: on a warm restore
    // the shell is already ready and will never *change* to ready.
    ref.listenManual(identityStatusProvider, (_, status) {
      if (status != IdentityStatus.ready) return;
      _maybeOpenFeed();
      unawaited(_maybePrompt());
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    unawaited(_taps?.cancel());
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // Back from the phone's settings, perhaps with the permission flipped.
    ref.invalidate(alertPermissionProvider);
    // iOS suspends the socket in the background; whatever landed meanwhile is
    // in the table, not in the feed.
    unawaited(ref.read(notificationFeedProvider.notifier).refresh());
  }

  bool get _shellReady =>
      ref.read(identityStatusProvider) == IdentityStatus.ready;

  void _maybeOpenFeed() {
    if (!_openPending || !_shellReady) return;
    _openPending = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final router = ref.read(routerProvider);
      // `router.state` throws until the first route has resolved — possible on
      // a cold-start tap from the tray.
      if (router.routerDelegate.currentConfiguration.isEmpty) {
        _openPending = true;
        Future<void>.delayed(const Duration(milliseconds: 200), () {
          if (mounted) _maybeOpenFeed();
        });
        return;
      }
      if (router.state.matchedLocation == Routes.notifications) return;
      router.push(Routes.notifications);
    });
  }

  /// Once per device: a sentence of why, then the OS prompt. Asking cold at
  /// launch is how apps get "Don't allow" — and on iOS that answer is final.
  Future<void> _maybePrompt() async {
    if (_promptChecked || !_shellReady) return;
    if (!ref.read(canSeeNotificationsProvider)) return;
    _promptChecked = true;

    final setup = ref.read(alertSetupProvider);
    if (await setup.promptAnswered()) return;

    // Let the shell land first; a dialog over a half-drawn POS reads as an
    // error.
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;

    final permission = await ref.read(alertPermissionProvider.future);
    if (permission != AlertPermission.notAsked) {
      // Already on (older Android), or already refused: nothing to ask.
      await setup.markPromptAnswered();
      return;
    }

    final navContext = ref
        .read(routerProvider)
        .routerDelegate
        .navigatorKey
        .currentContext;
    if (navContext == null || !navContext.mounted) {
      _promptChecked = false;
      return;
    }

    final allow = await showDialog<bool>(
      context: navContext,
      builder: (_) => const _AlertsPrePrompt(),
    );
    if (!mounted) return;
    if (allow == true) {
      await setup.request();
    } else {
      // "Not now" is an answer. Settings → Notifications is the way back.
      await setup.markPromptAnswered();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listened, not watched: this keeps the feed and its channel alive without
    // rebuilding the app under it on every arrival.
    ref.listen(notificationFeedProvider, (_, _) {});
    ref.listen(canSeeNotificationsProvider, (_, can) {
      if (can) unawaited(_maybePrompt());
    });
    return widget.child;
  }
}

class _AlertsPrePrompt extends StatelessWidget {
  const _AlertsPrePrompt();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.notifications_active_outlined, size: 32),
      title: const Text('Turn on order alerts?'),
      content: const Text(
        'Get alerts when orders are new, ready to serve, served or paid '
        'while ExtraHelper is open. You can change this any time in '
        'Settings.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Allow'),
        ),
      ],
    );
  }
}
