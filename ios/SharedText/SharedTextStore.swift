import Foundation

/// Il testo che un'altra app ha condiviso con Tacca, in attesa che l'app lo
/// legga.
///
/// Lo scrive l'estensione di condivisione (`TaccaShare`), che gira in un
/// processo suo senza nessun motore Dart, e lo legge l'app al rientro in
/// primo piano (`SharedTextBridge`): l'unico posto che vedono entrambi è
/// l'App Group. Un testo solo, non una coda: una condivisione nuova prende il
/// posto di una vecchia mai letta, che l'utente ha evidentemente lasciato
/// perdere.
///
/// Questo file è compilato in **entrambi** i target, Runner e TaccaShare.
enum SharedTextStore {
  /// Deve coincidere con `LiveSessionShared.appGroupId` e con gli
  /// entitlements di Runner e TaccaShare: è lo stesso App Group.
  static let appGroupId = "group.com.tverdohleb.tacca"

  static let pendingTextKey = "shared_text.pending"

  private static var defaults: UserDefaults? {
    UserDefaults(suiteName: appGroupId)
  }

  static func save(_ text: String) {
    defaults?.set(text, forKey: pendingTextKey)
  }

  /// Restituisce il testo in attesa e lo toglie.
  static func take() -> String? {
    guard let defaults = defaults,
          let text = defaults.string(forKey: pendingTextKey)
    else { return nil }
    defaults.removeObject(forKey: pendingTextKey)
    return text
  }
}
