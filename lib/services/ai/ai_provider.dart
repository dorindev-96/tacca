import 'dart:typed_data';

import 'dto/plan_dto.dart';

/// Immagine pronta per l'invio al provider: già compressa (§6.4).
class AiImage {
  final Uint8List bytes;
  final String mimeType;

  const AiImage(this.bytes, {this.mimeType = 'image/jpeg'});
}

/// Esito di un'estrazione: la [PlanDto] proposta e, se il parsing è fallito
/// due volte, il segnale che la scheda è il fallback `freeText` (§6.2).
class PlanExtraction {
  final PlanDto plan;

  /// `true` se [plan] è il fallback con la risposta grezza in un blocco
  /// `freeText`: la UI lo segnala in revisione.
  final bool usedFallback;

  /// Ultima risposta testuale del modello (mai loggata con la key).
  final String rawResponse;

  const PlanExtraction({
    required this.plan,
    required this.usedFallback,
    required this.rawResponse,
  });
}

/// I provider AI con un'implementazione: sono gli unici `id` che
/// `assets/ai/models.json` può nominare.
///
/// [value] è al tempo stesso l'id nel JSON e il prefisso delle chiavi nel
/// secure storage (`ai.<value>.apiKey`): cambiarlo scollega la key già
/// salvata dagli utenti.
enum AiProviderId {
  openRouter('openrouter'),
  anthropic('anthropic'),
  google('google');

  const AiProviderId(this.value);

  final String value;

  /// `null` se il valore non corrisponde a nessun provider implementato (o
  /// non è nemmeno una stringa): il catalogo scarta la voce invece di
  /// offrire un provider che non c'è.
  static AiProviderId? fromValue(Object? value) =>
      values.where((id) => id.value == value).firstOrNull;
}

/// Contratto dei provider AI (§6.1), implementato da OpenRouter, Anthropic
/// e Google.
/// Il provider effettivo dipende dalla scelta dell'utente nelle impostazioni:
/// la UI e i cubit dipendono solo da questa interfaccia.
abstract interface class AiProvider {
  /// Estrae una scheda strutturata da immagini e/o testo. Nessuna chiamata
  /// avviene senza un'azione esplicita dell'utente (RNF-07).
  Future<PlanExtraction> extractPlan({
    List<AiImage> images = const [],
    String? text,
    String? userHint,
  });

  /// Verifica che la key salvata sia valida ("test connessione", RF-08).
  /// Completa senza errori se la key è accettata; altrimenti lancia le
  /// eccezioni tipizzate di `ai_exception.dart`.
  Future<void> testConnection();
}
