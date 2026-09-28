import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Order alerts (flutter_local_notifications). FlutterAppDelegate forwards
    // UNUserNotificationCenter callbacks to plugins, but only once it is the
    // centre's delegate — without this, a banner raised while the app is in the
    // foreground is swallowed and a tap on one never reaches Dart.
    UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
