import 'dart:convert';

import '../../../core/errors/ai_exception.dart';
import '../ai_provider.dart';
import '../ai_selection.dart';
import '../plan_parser.dart';
import '../prompts.dart';
import 'chat_plan_provider.dart';

/// Chiavi di JSON Schema che lo structured output di Anthropic non accetta
/// (vincoli numerici e di lunghezza): lasciarle nello schema fa rifiutare la
/// richiesta con un 400. Le stesse regole restano scritte nel prompt, e la
/// validazione semantica vera è quella del [PlanParser].
const _unsupportedSchemaKeys = {
  'minItems',
  'maxItems',
  'minLength',
  'maxLength',
  'minimum',
  'maximum',
  'multipleOf',
  'pattern',
};

/// Lo schema §5.3 ripulito dei vincoli non supportati.
final Map<String, dynamic> _planSchema =
    _stripUnsupported(planJsonSchema) as Map<String, dynamic>;

Object? _stripUnsupported(Object? node) {
  if (node is Map<String, dynamic>) {
    return <String, dynamic>{
      for (final entry in node.entries)
        if (!_unsupportedSchemaKeys.contains(entry.key))
          entry.key: _stripUnsupported(entry.value),
    };
  }
  if (node is List) return [for (final item in node) _stripUnsupported(item)];
  return node;
}

/// Provider Anthropic (Messages API, §6.1).
///
/// Structured output via `output_config.format` per i modelli che lo
/// dichiarano nel catalogo. Tutta la pipeline §6.2 (due fasi, retry,
/// fallback), e il ripiego senza schema quando il modello lo rifiuta a
/// runtime (rischio S-02), sta in [ChatPlanProvider]: qui resta solo il
/// protocollo.
class AnthropicProvider extends ChatPlanProvider {
  AnthropicProvider({required super.selection, super.dio, super.parser})
    : super(baseUrl: 'https://api.anthropic.com/v1');

  /// Versione dell'API richiesta su ogni chiamata: Anthropic la pretende
  /// esplicita e la usa per non cambiare il contratto sotto ai client.
  static const _apiVersion = '2023-06-01';

  @override
  AiProviderId get id => AiProviderId.anthropic;

  @override
  String get providerName => 'Anthropic';

  @override
  Map<String, String> authHeaders(String apiKey) => {
    'x-api-key': apiKey,
    'anthropic-version': _apiVersion,
  };

  /// Verifica la key sull'elenco dei modelli: è la chiamata autenticata più
  /// economica dell'API (nessun token di generazione).
  @override
  Future<void> testConnection() =>
      getWithKey('/models', queryParameters: {'limit': 1});

  /// Una chiamata `POST /messages`; ritorna testo e `stop_reason`.
  @override
  Future<AiChatResult> sendChat({
    required AiSelection selection,
    required String system,
    required List<AiChatTurn> turns,
    required bool structured,
  }) async {
    final model = selection.model;
    final effort = model.effort;
    final data = await postJson(
      '/messages',
      selection: selection,
      structured: structured,
      body: {
        'model': model.id,
        // `max_tokens` è obbligatorio: è il tetto della singola risposta e,
        // insieme al pensiero del modello, decide se la scheda arriva intera.
        'max_tokens': model.maxOutputTokens,
        'system': system,
        'messages': [for (final turn in turns) _message(turn)],
        if (structured || effort != null)
          'output_config': {
            if (effort != null) 'effort': effort,
            if (structured)
              'format': {'type': 'json_schema', 'schema': _planSchema},
          },
      },
    );
    return _extractContent(data);
  }

  /// Un turno nel formato Anthropic: lista di blocchi di contenuto, con
  /// l'immagine (base64) prima del testo, come raccomanda la documentazione
  /// quando la domanda riguarda l'immagine stessa.
  Map<String, dynamic> _message(AiChatTurn turn) {
    final image = turn.image;
    return {
      'role': turn.role == AiChatRole.assistant ? 'assistant' : 'user',
      'content': [
        if (image != null)
          {
            'type': 'image',
            'source': {
              'type': 'base64',
              'media_type': image.mimeType,
              'data': base64Encode(image.bytes),
            },
          },
        {'type': 'text', 'text': turn.text},
      ],
    };
  }

  AiChatResult _extractContent(Map<String, dynamic> data) {
    final stopReason = data['stop_reason'];
    // I classificatori di sicurezza possono declinare la richiesta con un
    // 200: senza questo controllo la risposta vuota sembrerebbe un guasto.
    if (stopReason == 'refusal') throw ChatPlanProvider.refusal;

    final content = data['content'];
    final textContent = content is List
        ? content
              .whereType<Map<String, dynamic>>()
              .where((block) => block['type'] == 'text')
              .map((block) => block['text'])
              .whereType<String>()
              .join('\n')
        : '';
    if (textContent.trim().isEmpty) throw ChatPlanProvider.emptyResponse;

    logResponse(
      content: textContent,
      stopReason: stopReason is String ? stopReason : null,
      usage: data['usage'],
    );
    return AiChatResult(textContent, isTruncated: stopReason == 'max_tokens');
  }

  @override
  AiException exceptionForStatus(
    int status,
    String message, {
    String? modelId,
  }) {
    // Il credito esaurito arriva come 400 con un messaggio sul saldo, non
    // come stato dedicato: senza riconoscerlo finirebbe fra gli errori
    // generici e l'utente non saprebbe cosa fare.
    if (_isCreditExhausted(message)) {
      return const AiQuotaException(
        'Credito Anthropic esaurito: aggiungi credito su '
        'console.anthropic.com/settings/billing, oppure passa a un altro '
        'provider nelle impostazioni AI.',
      );
    }
    return switch (status) {
      401 || 403 => const AiAuthException(
        'API key Anthropic non valida o senza permessi: controllala nelle '
        'impostazioni AI.',
      ),
      429 => const AiQuotaException(
        'Troppe richieste ad Anthropic in poco tempo (o limite di utilizzo '
        'raggiunto): aspetta qualche istante e riprova.',
      ),
      529 => const AiNetworkException(
        'I server Anthropic sono momentaneamente sovraccarichi: riprova '
        'fra poco.',
      ),
      _ => AiNetworkException(message),
    };
  }

  bool _isCreditExhausted(String message) {
    final detail = message.toLowerCase();
    return detail.contains('credit balance') ||
        detail.contains('insufficient credit') ||
        detail.contains('billing');
  }
}
