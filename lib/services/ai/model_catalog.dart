import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'ai_provider.dart';

/// Un modello offerto all'utente nelle Impostazioni AI.
class AiModelOption {
  /// Identificatore del modello presso il suo provider (es.
  /// `google/gemini-3.7-flash` su OpenRouter, `claude-opus-5` su Anthropic,
  /// `gemini-3.7-flash` su Google).
  final String id;

  /// Nome mostrato in UI.
  final String label;

  /// Il modello accetta immagini (necessario per l'import da foto, RF-03).
  final bool supportsVision;

  /// Il modello supporta lo structured output nativo del suo provider
  /// (`response_format: json_schema` su OpenRouter, `output_config.format` su
  /// Anthropic, `generationConfig.responseSchema` su Google); altrimenti la
  /// richiesta usa il fallback prompt-based (§6.2, rischio S-02).
  final bool supportsJsonSchema;

  /// Tetto di token di output inviato al provider. Deve stare largo: una
  /// scheda di due giorni supera facilmente i 3.000 token di JSON e, sui
  /// modelli con reasoning, i token di pensiero consumano lo stesso budget. Se
  /// il budget finisce, la risposta arriva troncata e la scheda è amputata.
  final int maxOutputTokens;

  /// Chiede a OpenRouter `reasoning: {effort: "none"}` (§6.1): su modelli
  /// reasoning il "pensiero" può mangiarsi quasi tutto `maxOutputTokens`
  /// prima di arrivare al JSON, troncando la scheda anche con un budget
  /// generoso. Il compito qui è trascrizione/estrazione meccanica, non
  /// richiede catena di ragionamento: disattivarla libera il budget per
  /// l'output vero. Ignorato dagli altri provider.
  final bool disableReasoning;

  /// L'equivalente della riga sopra dove il pensiero non si spegne ma si
  /// dosa: `output_config.effort` su Anthropic (`low`…`max`) e
  /// `generationConfig.thinkingConfig.thinkingLevel` su Google (`low`,
  /// `medium`, `high`). `null` lascia il default del modello; Claude Haiku
  /// 4.5 non accetta il parametro e va lasciato senza, e Gemini 3.7 Flash
  /// rifiuta `minimal`. Ignorato da OpenRouter.
  final String? effort;

  const AiModelOption({
    required this.id,
    required this.label,
    this.supportsVision = false,
    this.supportsJsonSchema = false,
    this.maxOutputTokens = defaultMaxOutputTokens,
    this.disableReasoning = false,
    this.effort,
  });

  /// Valore usato quando `models.json` non lo specifica: prudente, accettato
  /// da tutti i modelli vision di uso comune.
  static const defaultMaxOutputTokens = 8192;
}

/// Un provider selezionabile con i suoi modelli.
///
/// [id] non è testo libero: è uno degli [AiProviderId] implementati, perché a
/// ogni provider corrisponde del codice che parla il suo protocollo.
class AiProviderOption {
  final AiProviderId id;

  /// Nome mostrato in UI.
  final String label;

  /// Modello usato finché l'utente non ne sceglie uno per questo provider.
  final String defaultModelId;

  /// Placeholder del campo API key (es. `sk-or-…`): dice che forma ha la key
  /// di questo provider. `null` lascia il testo generico delle traduzioni.
  final String? keyHint;

  final List<AiModelOption> models;

  const AiProviderOption({
    required this.id,
    required this.label,
    required this.defaultModelId,
    required this.models,
    this.keyHint,
  });

  AiModelOption? byId(String? modelId) =>
      models.where((model) => model.id == modelId).firstOrNull;

  /// Il modello di default, garantito presente: [AiModelCatalog] verifica in
  /// fase di parsing che [defaultModelId] esista fra i [models].
  AiModelOption get defaultModel => byId(defaultModelId) ?? models.first;

  /// Il modello salvato se esiste ancora nel catalogo, altrimenti il default:
  /// un id rimasto nelle impostazioni dopo una modifica del JSON non deve
  /// diventare una chiamata a un modello inesistente.
  AiModelOption modelOrDefault(String? modelId) =>
      byId(modelId) ?? defaultModel;
}

/// Catalogo dei provider e dei modelli selezionabili, letto da
/// `assets/ai/models.json`.
///
/// La lista è configurazione, non codice: per cambiare i modelli offerti (o
/// per riordinare i provider) basta modificare l'asset JSON. L'unico vincolo
/// è l'`id` del provider, che deve corrispondere a un [AiProviderId]
/// implementato: le voci con un id sconosciuto vengono scartate.
class AiModelCatalog {
  final AiProviderId defaultProviderId;
  final List<AiProviderOption> providers;

  const AiModelCatalog({
    required this.defaultProviderId,
    required this.providers,
  });

  static const assetPath = 'assets/ai/models.json';

  /// Carica il catalogo dagli asset. Chiamare in `main()` prima di `runApp`,
  /// come per lo Store ObjectBox: da lì in poi tutto è sincrono.
  static Future<AiModelCatalog> load() async {
    return AiModelCatalog.fromJsonString(
      await rootBundle.loadString(assetPath),
    );
  }

  /// Parsing separato dal caricamento asset per poterlo unit-testare.
  factory AiModelCatalog.fromJsonString(String source) {
    final root = jsonDecode(source);
    if (root is! Map<String, dynamic>) {
      throw const FormatException('models.json: atteso un oggetto JSON.');
    }

    final rawProviders = root['providers'];
    final providers = <AiProviderOption>[
      if (rawProviders is List)
        for (final entry in rawProviders.whereType<Map<String, dynamic>>())
          if (_providerFromJson(entry) case final provider?) provider,
    ];
    if (providers.isEmpty) {
      throw const FormatException('models.json: nessun provider valido.');
    }

    final defaultId = AiProviderId.fromValue(root['defaultProviderId']);
    return AiModelCatalog(
      defaultProviderId: providers.any((p) => p.id == defaultId)
          ? defaultId!
          : providers.first.id,
      providers: providers,
    );
  }

  AiProviderOption? byId(AiProviderId? id) =>
      providers.where((provider) => provider.id == id).firstOrNull;

  /// Il provider di default, garantito presente in [providers].
  AiProviderOption get defaultProvider =>
      byId(defaultProviderId) ?? providers.first;

  /// Il provider salvato se è ancora nel catalogo, altrimenti il default.
  AiProviderOption providerOrDefault(String? providerId) =>
      byId(AiProviderId.fromValue(providerId)) ?? defaultProvider;

  /// Una voce di `providers`: `null` se l'id non è implementato o se non
  /// resta nemmeno un modello valido.
  static AiProviderOption? _providerFromJson(Map<String, dynamic> entry) {
    final id = AiProviderId.fromValue(entry['id']);
    if (id == null) return null;

    final rawModels = entry['models'];
    final models = <AiModelOption>[
      if (rawModels is List)
        for (final model in rawModels.whereType<Map<String, dynamic>>())
          if (_modelFromJson(model) case final option?) option,
    ];
    if (models.isEmpty) return null;

    final defaultModel = models
        .where((model) => model.id == entry['defaultModelId'])
        .firstOrNull;
    return AiProviderOption(
      id: id,
      label: _text(entry['label']) ?? id.value,
      keyHint: _text(entry['keyHint']),
      defaultModelId: (defaultModel ?? models.first).id,
      models: models,
    );
  }

  /// Una voce di `models`: `null` se manca l'id, senza il quale il modello
  /// non si può chiedere al provider.
  static AiModelOption? _modelFromJson(Map<String, dynamic> entry) {
    final id = _text(entry['id']);
    if (id == null || id.isEmpty) return null;
    return AiModelOption(
      id: id,
      label: _text(entry['label']) ?? id,
      supportsVision: entry['supportsVision'] == true,
      supportsJsonSchema: entry['supportsJsonSchema'] == true,
      maxOutputTokens: switch (entry['maxOutputTokens']) {
        final int value when value > 0 => value,
        _ => AiModelOption.defaultMaxOutputTokens,
      },
      disableReasoning: entry['disableReasoning'] == true,
      effort: _text(entry['effort']),
    );
  }
}

/// Il valore di un campo testuale di `models.json`; `null` se manca o non è
/// una stringa.
String? _text(Object? value) => value is String ? value : null;
