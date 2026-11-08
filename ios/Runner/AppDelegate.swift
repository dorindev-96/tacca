import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  /// Ponte della Live Activity: tenuto vivo dall'AppDelegate perché il canale
  /// deve rispondere per tutta la vita dell'app.
  private var liveSession: LiveSessionBridge?

  /// Ponte del testo condiviso con l'app dall'estensione `TaccaShare`.
  private var sharedText: SharedTextBridge?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Necessario a flutter_local_notifications per presentare i segnali dei
    // timer anche mentre l'app è in primo piano (§7).
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    }
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      liveSession = LiveSessionBridge(messenger: controller.binaryMessenger)
      sharedText = SharedTextBridge(messenger: controller.binaryMessenger)
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// `tacca://shared-text` è l'URL con cui l'estensione di condivisione
  /// riporta l'app in primo piano dopo aver lasciato il testo nell'App Group.
  /// Non c'è niente da fare con l'URL in sé: il testo lo chiede il Dart al
  /// rientro. Si risponde `true` perché nessun altro deve provare a
  /// interpretarlo come deep link (e `FlutterDeepLinkingEnabled` è spento in
  /// Info.plist: l'app non ne ha).
  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if url.scheme == "tacca" { return true }
    return super.application(app, open: url, options: options)
  }
}
