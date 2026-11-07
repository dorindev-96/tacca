import 'app_exception.dart';

/// Base delle eccezioni del servizio AI (§6.5).
///
/// La UI distingue i sottotipi per dare messaggi parlanti: key invalida,
/// quota/crediti esauriti, rete assente (analisi funzionale §9). Li traduce
/// `AiFailure.from` (`ai_failure.dart`); il [message] resta diagnostica e non
/// arriva mai a schermo.
class AiException extends AppException {
  const AiException(super.message, {super.cause});
}

/// API key assente, invalida o revocata (HTTP 401/403).
class AiAuthException extends AiException {
  const AiAuthException(super.message, {super.cause});
}

/// Crediti o quota esauriti, rate limit (HTTP 402/429).
class AiQuotaException extends AiException {
  const AiQuotaException(super.message, {super.cause});
}

/// Errore di rete o del provider non riconducibile a key/quota.
class AiNetworkException extends AiException {
  const AiNetworkException(super.message, {super.cause});
}

/// Funzioni AI non configurate (nessuna key salvata): la UI rimanda
/// alle impostazioni invece di tentare la chiamata.
class AiConfigurationException extends AiException {
  const AiConfigurationException(super.message, {super.cause});
}

/// Risposta del modello vuota o strutturalmente inutilizzabile a livello
/// di trasporto (non è un errore di parsing: quello passa dal retry §6.2).
class AiResponseException extends AiException {
  const AiResponseException(super.message, {super.cause});
}
