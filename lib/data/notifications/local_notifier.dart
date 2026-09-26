import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import 'app_notification.dart';

/// Where this phone stands on showing alerts.
enum AlertPermission {
  /// The OS will show them.
  granted,

  /// Off, and the OS will still show its own prompt if asked.
  notAsked,

  /// Off, and the OS will not ask again — only the phone's settings can turn
  /// it back on.
  blocked,
}

/// The OS permission, decided from what the platform reports plus how many
/// times this device has been told "no".
///
/// Neither platform will say outright whether a prompt is still possible.
/// iOS asks exactly once, ever. Android 13+ shows the prompt at most twice and
/// then silently refuses on the user's behalf. So the device counts refusals
/// ([denials]) and treats reaching the platform's limit as [blocked].
AlertPermission resolveAlertPermission({
  required bool enabled,
  required int denials,
  required bool isIOS,
}) {
  if (enabled) return AlertPermission.granted;
  final limit = isIOS ? 1 : 2;
  return denials >= limit ? AlertPermission.blocked : AlertPermission.notAsked;
}

/// OS notifications on this device — the banner, the sound, the lock-screen
/// row.
///
/// **Limitation, and it is a big one:** these are *local* notifications,
/// raised by this app from a Realtime event it received itself. They arrive
/// while the app is open or backgrounded-but-alive. When the OS has killed the
/// app (swiped away, or reclaimed overnight) there is no socket and nothing
/// arrives. That needs server push through FCM/APNs — phase 2.
class LocalNotifier {
  LocalNotifier([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  final _taps = StreamController<String?>.broadcast();
  bool _ready = false;

  /// High importance so Android shows a heads-up banner rather than a silent
  /// tray row — a "Ready to serve" that nobody sees is a cold plate. Channel
  /// settings are fixed the first time the channel exists; changing them later
  /// means a new channel id.
  static const channel = AndroidNotificationChannel(
    'orders',
    'Orders',
    description: 'New orders, ready dishes, served tables and payments',
    importance: Importance.high,
  );

  /// Taps on a notification while the app is running. Carries the payload
  /// (the order id, else the bill id).
  Stream<String?> get taps => _taps.stream;

  /// The payload of the notification that launched the app, if one did.
  String? launchPayload;
  bool launchedFromNotification = false;

  /// Safe to call once at startup. Never prompts: iOS is told not to ask here,
  /// so the question arrives with a reason attached (see `NotifyLoop`).
  Future<void> init() async {
    if (_ready || !(Platform.isAndroid || Platform.isIOS)) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          // A monochrome vector: Android paints the status-bar icon from its
          // alpha alone, so the full-colour launcher icon becomes a white
          // square. `res/raw/keep.xml` stops R8 stripping it in release.
          android: AndroidInitializationSettings('ic_stat_notify'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (r) => _taps.add(r.payload),
      );
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel);

      final launch = await _plugin.getNotificationAppLaunchDetails();
      launchedFromNotification = launch?.didNotificationLaunchApp ?? false;
      launchPayload = launch?.notificationResponse?.payload;
      _ready = true;
    } catch (e) {
      // Alerts are a convenience. A plugin that fails to start must not keep
      // the till from opening.
      debugPrint('LocalNotifier.init failed: $e');
    }
  }

  /// Whether the OS will currently show this app's notifications.
  Future<bool> isEnabled() async {
    if (!_ready) return false;
    try {
      if (Platform.isAndroid) {
        return await _plugin
                .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin
                >()
                ?.areNotificationsEnabled() ??
            false;
      }
      final opts = await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.checkPermissions();
      return opts?.isEnabled ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Shows the OS prompt. Android 13+ and iOS only; older Android has
  /// notifications on by default and returns the current state.
  Future<bool> requestPermission() async {
    if (!_ready) return false;
    try {
      if (Platform.isAndroid) {
        return await _plugin
                .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin
                >()
                ?.requestNotificationsPermission() ??
            false;
      }
      return await _plugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// The phone's own notification settings for this app — the only way back
  /// once the OS has stopped asking.
  Future<void> openSettings() async {
    bool? opened;
    try {
      if (Platform.isAndroid) {
        opened = await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.openAppNotificationSettings();
      } else if (Platform.isIOS) {
        opened = await _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.openAppNotificationSettings();
      }
    } catch (_) {
      opened = false;
    }
    if (opened != true) await ph.openAppSettings();
  }

  /// Raise the banner. [detail] is the body line, already formatted with the
  /// tenant's currency by the caller.
  Future<void> show(AppNotification n, {required String detail}) async {
    if (!_ready) return;
    try {
      await _plugin.show(
        id: n.osId,
        title: n.title,
        body: detail,
        payload: n.payload,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            channel.id,
            channel.name,
            channelDescription: channel.description,
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.event,
            ticker: n.title,
            when: n.createdAt.millisecondsSinceEpoch,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBanner: true,
            presentList: true,
            presentSound: true,
          ),
        ),
      );
    } catch (e) {
      debugPrint('LocalNotifier.show failed: $e');
    }
  }

  void dispose() => unawaited(_taps.close());
}

/// Overridden in `main()` with the instance that was initialised before the
/// first frame, so a launch-from-notification payload is not lost.
final localNotifierProvider = Provider<LocalNotifier>((ref) {
  final notifier = LocalNotifier();
  ref.onDispose(notifier.dispose);
  return notifier;
});
