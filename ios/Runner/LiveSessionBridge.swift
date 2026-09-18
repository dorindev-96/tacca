import Flutter
import Foundation
import UserNotifications

#if canImport(ActivityKit)
import ActivityKit
#endif

/// Ponte fra il Dart (`IosLiveSessionController`) e ActivityKit.
///
/// L'app avvia e aggiorna la Live Activity; il **pulsante** invece non passa
/// di qui: `CompleteSetIntent` viene eseguito da iOS anche ad app sospesa,
/// senza motore Dart, e lascia l'azione nella coda dell'App Group, che questo
/// ponte svuota con `drainPendingActions`.
///
/// ActivityKit esiste da iOS 16.1 e l'API usata qui (`ActivityContent`) da
/// 16.2: sotto, `isSupported` risponde `false` e la sessione funziona come
/// prima, senza banner.
final class LiveSessionBridge {
  static let channelName = "tacca/live_session"

  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: LiveSessionBridge.channelName,
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isSupported":
      result(isSupported)
    case "start":
      start(payload: call.arguments as? [String: Any] ?? [:])
      result(nil)
    case "update":
      update(payload: call.arguments as? [String: Any] ?? [:])
      result(nil)
    case "stop":
      stop()
      result(nil)
    case "drainPendingActions":
      result(PendingActionStore.drain())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private var isSupported: Bool {
    if #available(iOS 16.2, *) {
      return ActivityAuthorizationInfo().areActivitiesEnabled
    }
    return false
  }

  private func start(payload: [String: Any]) {
    guard #available(iOS 16.2, *), isSupported else { return }
    let attributes = LiveSessionBridge.attributes(from: payload)
    let state = LiveSessionBridge.contentState(from: payload)
    // L'app ha ripreso in mano i timer: la notifica programmata
    // dall'estensione non serve più e suonerebbe due volte.
    cancelRestReminder()
    Task {
      await LiveSessionBridge.endAllActivities()
      do {
        _ = try Activity<TaccaSessionAttributes>.request(
          attributes: attributes,
          content: ActivityContent(state: state, staleDate: nil),
          pushType: nil
        )
      } catch {
        NSLog("[tacca] Live Activity non avviata: \(error.localizedDescription)")
      }
    }
  }

  private func update(payload: [String: Any]) {
    guard #available(iOS 16.2, *) else { return }
    let state = LiveSessionBridge.contentState(from: payload)
    cancelRestReminder()
    Task {
      guard let activity = Activity<TaccaSessionAttributes>.activities.first else { return }
      await activity.update(ActivityContent(state: state, staleDate: nil))
    }
  }

  private func stop() {
    PendingActionStore.clear()
    cancelRestReminder()
    guard #available(iOS 16.2, *) else { return }
    Task { await LiveSessionBridge.endAllActivities() }
  }

  private func cancelRestReminder() {
    UNUserNotificationCenter.current().removePendingNotificationRequests(
      withIdentifiers: [LiveSessionShared.restReminderId]
    )
  }

  /// Una sola sessione per volta: quello che è rimasto aperto da un avvio
  /// precedente (crash, riapertura) si chiude prima di ripartire.
  @available(iOS 16.2, *)
  private static func endAllActivities() async {
    for activity in Activity<TaccaSessionAttributes>.activities {
      await activity.end(nil, dismissalPolicy: .immediate)
    }
  }

  @available(iOS 16.1, *)
  private static func attributes(from payload: [String: Any]) -> TaccaSessionAttributes {
    TaccaSessionAttributes(
      logId: payload["logId"] as? Int ?? 0,
      title: payload["title"] as? String ?? "",
      setsLabel: payload["setsLabel"] as? String ?? "",
      completeAction: payload["completeAction"] as? String ?? "",
      restLabel: payload["restLabel"] as? String ?? "",
      restDoneLabel: payload["restDoneLabel"] as? String ?? ""
    )
  }

  @available(iOS 16.1, *)
  private static func contentState(
    from payload: [String: Any]
  ) -> TaccaSessionAttributes.ContentState {
    TaccaSessionAttributes.ContentState(
      exerciseName: payload["exerciseName"] as? String ?? "",
      entryIndex: payload["entryIndex"] as? Int ?? 0,
      setNumber: payload["setNumber"] as? Int ?? 0,
      totalSets: payload["totalSets"] as? Int ?? 0,
      canCompleteSet: payload["canCompleteSet"] as? Bool ?? false,
      advancesToNext: payload["advancesToNext"] as? Bool ?? false,
      restSecondsOnComplete: payload["restSecondsOnComplete"] as? Int ?? 0,
      countdownStartsAt: LiveSessionBridge.date(payload["countdownStartsAt"]),
      countdownEndsAt: LiveSessionBridge.date(payload["countdownEndsAt"]),
      countdownLabel: payload["countdownLabel"] as? String,
      nextExerciseName: payload["nextExerciseName"] as? String,
      nextEntryIndex: payload["nextEntryIndex"] as? Int ?? 0,
      nextSetNumber: payload["nextSetNumber"] as? Int ?? 0,
      nextTotalSets: payload["nextTotalSets"] as? Int ?? 0,
      nextRestSecondsOnComplete: payload["nextRestSecondsOnComplete"] as? Int ?? 0,
      nextAdvancesToNext: payload["nextAdvancesToNext"] as? Bool ?? false
    )
  }

  /// Il Dart manda millisecondi dall'epoca: è l'unico formato temporale che
  /// attraversa il MethodChannel senza sorprese di fuso.
  private static func date(_ raw: Any?) -> Date? {
    guard let millis = raw as? Int else { return nil }
    return Date(timeIntervalSince1970: TimeInterval(millis) / 1000)
  }
}
