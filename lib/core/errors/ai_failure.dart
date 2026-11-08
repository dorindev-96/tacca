import '../../l10n/app_localizations.dart';
import 'ai_exception.dart';

/// Perché una chiamata all'AI non è riuscita, detto come serve alla pagina:
/// per scegliere il messaggio.
///
/// Nasce dal sottotipo di [AiException]. Il `message` dell'eccezione resta
/// diagnostica (log, test, ritorno al modello) e non arriva mai a schermo: è
/// scritto in una lingua sola e parla di HTTP, mentre chi legge vuole sapere
/// cosa fare.
enum AiFailure {
  /// Key assente, invalida o revocata.
  auth,

  /// Crediti o quota esauriti, rate limit.
  quota,

  /// Rete assente o provider irraggiungibile.
  network,

  /// Il provider ha risposto, ma con qualcosa di inutilizzabile.
  response,

  /// Nessuna key salvata per il provider scelto.
  notConfigured,

  /// Solo dall'import: il modello scelto non legge le immagini e l'OCR del
  /// telefono non ci ha trovato testo. Non nasce da un'eccezione.
  imagesUnreadable,

  /// Tutto il resto: un errore che nessuno ha previsto.
  unexpected;

  /// Il fallimento corrispondente a [error], qualunque cosa sia.
  static AiFailure from(Object error) => switch (error) {
    AiAuthException() => auth,
    AiQuotaException() => quota,
    AiNetworkException() => network,
    AiResponseException() => response,
    AiConfigurationException() => notConfigured,
    _ => unexpected,
  };

  /// Il messaggio da mostrare, nella lingua dell'interfaccia.
  String message(AppLocalizations l10n) => switch (this) {
    auth => l10n.aiFailureAuth,
    quota => l10n.aiFailureQuota,
    network => l10n.aiFailureNetwork,
    response => l10n.aiFailureResponse,
    notConfigured => l10n.aiFailureNotConfigured,
    imagesUnreadable => l10n.aiFailureImagesUnreadable,
    unexpected => l10n.aiFailureUnexpected,
  };
}
