import Flutter
import UIKit

/// Foglio di condivisione per il **testo** (il prompt dell'import senza key e
/// il messaggio di correzione), presentato da noi invece che da share_plus.
///
/// Esiste per un difetto di UIKit che share_plus non gestisce: quando
/// l'estensione di condivisione scelta chiude la richiesta prima che la sua
/// vista sia comparsa — è quello che fa un'estensione che rimanda subito alla
/// propria app, come Gemini — UIKit prova a chiudere il contenitore prima di
/// averlo presentato, e il contenitore resta sopra l'app, invisibile, a
/// prendersi tutti i tocchi. Dalla lista "Altro" del foglio la catena delle
/// viste è più lunga e il problema si vede sempre: tornati in Tacca, l'app
/// sembra congelata. Qui facciamo tre cose che il plugin non fa:
///
/// 1. si risponde al Dart **una volta sola**, anche se la completion di
///    sistema arriva più volte (aprire "Altro" può farla scattare con
///    `completed == false` mentre il foglio è ancora a schermo: non è una
///    chiusura, e si aspetta la chiamata vera);
/// 2. a condivisione finita si chiude **tutto** ciò che il controller da cui
///    abbiamo presentato ha ancora sopra di sé: dopo la fine non c'è niente
///    di legittimo da tenere;
/// 3. se durante la condivisione l'app è andata in background e torna in
///    primo piano senza che la completion sia arrivata, la condivisione è
///    uscita verso un'altra app: si risponde `shared` e si fa la stessa
///    pulizia.
///
/// Le immagini delle schede e il backup passano ancora da share_plus: sono
/// file, e le estensioni che li ricevono non hanno mostrato il problema.
final class TextShareBridge: NSObject {
  static let channelName = "tacca/text_share"

  private let channel: FlutterMethodChannel
  private weak var rootController: UIViewController?
  private var session: ShareSession?

  init(messenger: FlutterBinaryMessenger, rootController: UIViewController) {
    channel = FlutterMethodChannel(
      name: TextShareBridge.channelName,
      binaryMessenger: messenger
    )
    self.rootController = rootController
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      switch call.method {
      case "share":
        self.share(arguments: call.arguments as? [String: Any] ?? [:], result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    let center = NotificationCenter.default
    center.addObserver(
      self, selector: #selector(appDidEnterBackground),
      name: UIApplication.didEnterBackgroundNotification, object: nil)
    center.addObserver(
      self, selector: #selector(appDidBecomeActive),
      name: UIApplication.didBecomeActiveNotification, object: nil)
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  private func share(arguments: [String: Any], result: @escaping FlutterResult) {
    guard let text = arguments["text"] as? String, !text.isEmpty,
          let presenter = topController()
    else {
      result("unavailable")
      return
    }
    // Una condivisione precedente rimasta appesa non deve bloccare la nuova.
    if let previous = session {
      previous.resolve("dismissed")
      finish(previous)
    }

    let activity = UIActivityViewController(activityItems: [text], applicationActivities: nil)
    if let subject = arguments["subject"] as? String {
      activity.setValue(subject, forKey: "subject")
    }
    if let popover = activity.popoverPresentationController {
      popover.sourceView = presenter.view
      popover.sourceRect = TextShareBridge.rect(arguments["origin"], in: presenter.view)
    }

    let current = ShareSession(activity: activity, presenter: presenter, result: result)
    session = current

    activity.completionWithItemsHandler = { [weak self, weak current] _, completed, _, _ in
      // Mezzo secondo perché il foglio finisca la sua animazione: è il modo
      // di distinguere "Altro" (foglio ancora a schermo) da una chiusura.
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        guard let self = self, let current = current, self.session === current else { return }
        // Foglio ancora a schermo (con o senza la lista "Altro" sopra): non
        // è una chiusura, si aspetta la prossima chiamata o il ritorno
        // dall'altra app.
        if !completed && current.activityOnScreen { return }
        current.resolve(completed ? "shared" : "dismissed")
        self.finish(current)
      }
    }

    presenter.present(activity, animated: true)
  }

  @objc private func appDidEnterBackground() {
    session?.wentToBackground = true
  }

  @objc private func appDidBecomeActive() {
    guard let current = session, current.wentToBackground else { return }
    // Il tempo che UIKit chiuda da sé quello che sa chiudere.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
      guard let self = self, self.session === current else { return }
      current.resolve("shared")
      self.finish(current)
    }
  }

  /// Toglie tutto quello che la condivisione ha lasciato sopra al controller
  /// da cui è partita, e chiude la sessione.
  private func finish(_ finished: ShareSession) {
    if session === finished { session = nil }
    guard let presenter = finished.presenter,
          let presented = presenter.presentedViewController,
          !presented.isBeingDismissed
    else { return }
    presenter.dismiss(animated: false)
  }

  private func topController() -> UIViewController? {
    var top = rootController
    while let presented = top?.presentedViewController, !presented.isBeingDismissed {
      top = presented
    }
    return top
  }

  /// L'ancora del popover su iPad: il rettangolo passato dal Dart, o il
  /// centro della vista se non c'è.
  private static func rect(_ raw: Any?, in view: UIView) -> CGRect {
    if let values = raw as? [Double], values.count == 4, values[2] > 0, values[3] > 0 {
      return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
    }
    return CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
  }
}

/// Una condivisione in corso.
private final class ShareSession {
  let activity: UIActivityViewController
  weak var presenter: UIViewController?
  private var result: FlutterResult?
  var wentToBackground = false

  init(activity: UIActivityViewController, presenter: UIViewController, result: @escaping FlutterResult) {
    self.activity = activity
    self.presenter = presenter
    self.result = result
  }

  var activityOnScreen: Bool {
    activity.viewIfLoaded?.window != nil && !activity.isBeingDismissed
  }

  /// Risponde al Dart una volta sola: le chiamate successive non fanno niente.
  func resolve(_ value: String) {
    guard let pending = result else { return }
    result = nil
    pending(value)
  }
}
