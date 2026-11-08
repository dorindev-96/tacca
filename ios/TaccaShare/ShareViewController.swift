import UIKit
import UniformTypeIdentifiers

/// L'estensione di condivisione di Tacca: compare nell'elenco delle app
/// quando si condivide un testo, lo mette nell'App Group e riapre l'app.
///
/// È il viaggio di ritorno dell'import senza API key (RF-03): dalla chat AI
/// l'utente tocca *Condividi* sulla risposta, sceglie Tacca, e la risposta
/// arriva nell'app senza passare dagli appunti. L'estensione gira in un
/// processo suo, senza Flutter e senza database: non interpreta niente, non
/// mostra niente (nessuna interfaccia: la vista è trasparente e si chiude da
/// sola). A decidere cosa fare del testo è l'app, `AiPasteImportCubit`.
///
/// Compilato nel solo target `TaccaShare`; `SharedTextStore` è condiviso con
/// l'app (vedi `ios/SharedText/`).
final class ShareViewController: UIViewController {
  /// Lo stesso schema dichiarato in `Runner/Info.plist` (`CFBundleURLTypes`)
  /// e riconosciuto da `AppDelegate`.
  private static let hostAppUrl = URL(string: "tacca://shared-text")!

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .clear
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    loadSharedText { [weak self] text in
      guard let self = self else { return }
      if let text = text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        SharedTextStore.save(text)
        self.openHostApp()
      }
      self.extensionContext?.completeRequest(returningItems: nil)
    }
  }

  /// Il primo attachment testuale fra quelli ricevuti. Un testo può viaggiare
  /// come `public.plain-text` oppure, da alcune app, come URL: si accettano
  /// entrambi, perché per il parser dell'app è comunque testo da leggere.
  private func loadSharedText(completion: @escaping (String?) -> Void) {
    let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
    let providers = items.flatMap { $0.attachments ?? [] }
    let types = [UTType.plainText.identifier, UTType.text.identifier, UTType.url.identifier]
    for type in types {
      if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(type) }) {
        provider.loadItem(forTypeIdentifier: type, options: nil) { item, _ in
          let text: String?
          switch item {
          case let string as String: text = string
          case let data as Data: text = String(data: data, encoding: .utf8)
          case let url as URL: text = url.absoluteString
          case let attributed as NSAttributedString: text = attributed.string
          default: text = nil
          }
          DispatchQueue.main.async { completion(text) }
        }
        return
      }
    }
    // Nessun attachment: alcune app mettono il testo direttamente nell'item.
    completion(items.first?.attributedContentText?.string)
  }

  /// Un'estensione non può chiamare `UIApplication.shared.open`: si risale la
  /// catena dei responder fino a chi risponde a `openURL:`, che nel processo
  /// dell'estensione è l'oggetto applicazione di sistema. È lo stesso
  /// meccanismo usato dalle librerie di condivisione per Flutter.
  private func openHostApp() {
    let selector = sel_registerName("openURL:")
    var responder: UIResponder? = self
    while let current = responder {
      if current !== self, current.responds(to: selector) {
        current.perform(selector, with: ShareViewController.hostAppUrl)
        return
      }
      responder = current.next
    }
  }
}
