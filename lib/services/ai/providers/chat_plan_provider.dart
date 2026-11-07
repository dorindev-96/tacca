import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/errors/ai_exception.dart';
import '../../../core/extensions/blank_text.dart';
import '../ai_provider.dart';
import '../ai_selection.dart';
import '../plan_merge.dart';
import '../plan_normalizer.dart';
import '../plan_parser.dart';
import '../prompts.dart';

/// Chi ha scritto un turno della conversazione con il modello.
enum AiChatRole { user, assistant }

/// Un turno neutro rispetto al provider: del testo e, nella fase di
/// trascrizione, l'immagine da leggere. Ogni implementazione lo traduce nel
/// formato della propria API (`messages` OpenAI-compatible, blocchi di
/// contenuto Anthropic, …).
class AiChatTurn {
  final AiChatRole role;
  final String text;
  final AiImage? image;

  const AiChatTurn.user(this.text, {this.image}) : role = AiChatRole.user;

  const AiChatTurn.assistant(this.text)
    : role = AiChatRole.assistant,
      image = null;
}

/// Esito normalizzato di una singola chiamata al modello: il testo e il
/// segnale che la generazione si è fermata per budget esaurito.
class AiChatResult {
  final String content;

  /// La risposta è stata tagliata dal tetto di token di output (OpenRouter:
  /// `finish_reason: length`; Anthropic: `stop_reason: max_tokens`).
  final bool isTruncated;

  const AiChatResult(this.content, {this.isTruncated = false});
}

/// Venti cifre uguali di fila non esistono in una scheda: è il loop del
/// sampler sotto grammatica vincolata.
final _degenerateDigits = RegExp(r'(\d)\1{19,}');

/// Il modello ha rifiutato lo structured output: [ChatPlanProvider] rifà la
/// stessa richiesta senza schema. Non esce mai da questo file.
class _StructuredOutputRejected implements Exception {
  const _StructuredOutputRejected();
}

/// La pipeline §6.2 condivisa da tutti i provider basati su chat.
///
/// Qui sta tutto ciò che non dipende dal protocollo: le due fasi per pagina
/// (prima leggere, poi strutturare), il retry correttivo, il fallback
/// `freeText`, la fusione delle pagine, i controlli sulle risposte
/// degenerate e il trasporto che le API hanno in comune — client HTTP,
/// ripiego senza structured output (S-02), errori di rete e di stato. Alle
/// sottoclassi resta il protocollo: [sendChat] traduce i turni nella
/// richiesta della loro API e ne riporta testo e troncamento, [authHeaders]
/// ed [exceptionForStatus] dicono come viaggia la key e cosa vogliono dire i
/// loro errori HTTP.
///
/// La key viene letta dalle impostazioni a ogni chiamata e finisce solo negli
/// header: mai nei log, mai nelle eccezioni (RNF-03).
abstract class ChatPlanProvider implements AiProvider {
  ChatPlanProvider({
    required AiSelectionResolver selection,
    required String baseUrl,
    Dio? dio,
    PlanParser parser = const PlanParser(),
  }) : _selection = selection,
       _parser = parser,
       _dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: baseUrl,
               connectTimeout: const Duration(seconds: 15),
               // Le estrazioni vision su schede dense possono essere lente.
               receiveTimeout: const Duration(minutes: 3),
             ),
           );

  final AiSelectionResolver _selection;
  final PlanParser _parser;
  final Dio _dio;

  /// Il modello ha risposto senza testo.
  static const emptyResponse = AiResponseException(
    'Il modello ha restituito una risposta vuota.',
  );

  /// Il modello, o un filtro a monte, ha declinato la richiesta: la risposta
  /// arriva con un 200 e senza testo, e senza dirlo sembrerebbe un guasto.
  static const refusal = AiResponseException(
    'Il modello ha rifiutato di elaborare il contenuto inviato. '
    'Riprova con una foto o un testo diverso, oppure cambia modello '
    'nelle impostazioni AI.',
  );

  /// Quale provider è questo: serve a risolvere key e modello suoi, anche
  /// mentre nelle impostazioni è selezionato un altro.
  AiProviderId get id;

  /// Il nome del provider nei messaggi d'errore.
  @protected
  String get providerName;

  /// Gli header con cui [apiKey] arriva alla sua API.
  @protected
  Map<String, String> authHeaders(String apiKey);

  /// L'eccezione tipizzata di una risposta HTTP d'errore. [message] è quello
  /// del provider, o uno generico se il corpo non ne porta; [modelId] è il
  /// modello della richiesta, quando è una generazione.
  @protected
  AiException exceptionForStatus(int status, String message, {String? modelId});

  /// Manda una richiesta al modello e riporta il testo della risposta.
  ///
  /// [structured] chiede lo structured output nativo del provider. La
  /// richiesta passa da [postJson]: se il modello rifiuta lo schema a runtime
  /// (rischio S-02) riparte da sola senza, e il JSON viene poi estratto dal
  /// testo dal [PlanParser].
  @protected
  Future<AiChatResult> sendChat({
    required AiSelection selection,
    required String system,
    required List<AiChatTurn> turns,
    required bool structured,
  });

  /// `POST` di [body] a [path] con la key di [selection]: ritorna il corpo
  /// della risposta, o lancia le eccezioni tipizzate di `ai_exception.dart`.
  ///
  /// Una richiesta [structured] rifiutata come tale — HTTP 400/404/422 che non
  /// sia un problema di key o di quota — riparte una volta senza schema (S-02).
  /// Solo un rifiuto della *richiesta* giustifica il secondo tentativo: key
  /// invalida (Google la segnala proprio con un 400) o quota finita darebbero
  /// lo stesso errore due volte.
  @protected
  Future<Map<String, dynamic>> postJson(
    String path, {
    required AiSelection selection,
    required bool structured,
    required Map<String, dynamic> body,
  }) async {
    final Response<Object?> response;
    try {
      response = await _dio.post<Object?>(
        path,
        data: body,
        options: _authOptions(selection.requireApiKey()),
      );
    } on DioException catch (e) {
      final error = _mapDioException(e, modelId: selection.model.id);
      final status = e.response?.statusCode;
      if (structured &&
          (status == 400 || status == 404 || status == 422) &&
          error is! AiAuthException &&
          error is! AiQuotaException) {
        throw const _StructuredOutputRejected();
      }
      throw error;
    }

    final data = response.data;
    if (data is! Map<String, dynamic>) {
      throw const AiResponseException(
        'Risposta del provider non riconosciuta.',
      );
    }
    return data;
  }

  /// `GET` di [path] con la key di questo provider: è così che le
  /// implementazioni verificano la key in [testConnection].
  @protected
  Future<void> getWithKey(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    final apiKey = (await _selection.resolveFor(id)).requireApiKey();
    try {
      await _dio.get<Object?>(
        path,
        queryParameters: queryParameters,
        options: _authOptions(apiKey),
      );
    } on DioException catch (e) {
      throw _mapDioException(e);
    }
  }

  @override
  Future<PlanExtraction> extractPlan({
    List<AiImage> images = const [],
    String? text,
    String? userHint,
  }) async {
    final selection = await _selection.resolveFor(id);
    // Senza key la chiamata non parte.
    selection.requireApiKey();

    if (images.isEmpty) {
      return _structure(selection, sourceText: text ?? '', userHint: userHint);
    }

    // Una richiesta per pagina, e due fasi per pagina: prima leggere, poi
    // strutturare. Una sola chiamata su più foto costringe il modello a
    // produrre in un colpo il JSON dell'intera scheda, ed è lì che le schede
    // lunghe si accorciano. Le parti si fondono dopo.
    final pastedText = text.trimmedOrNull;
    final parts = <PlanExtraction>[];
    for (final (i, image) in images.indexed) {
      final transcript = await _transcribe(
        selection,
        image: image,
        pageIndex: i + 1,
        pageCount: images.length,
      );
      // Il testo incollato appartiene alla scheda intera: va unito a una
      // pagina sola, altrimenti ogni pagina ne ripeterebbe i giorni.
      final source = i == 0 && pastedText != null
          ? '$transcript\n\n$pastedText'
          : transcript;
      parts.add(
        await _structure(
          selection,
          sourceText: source,
          userHint: userHint,
          pageIndex: i + 1,
          pageCount: images.length,
        ),
      );
    }

    if (parts.length == 1) return parts.single;
    // La fusione riaccosta blocchi che venivano da pagine diverse (un giorno
    // che prosegue sulla pagina dopo): la forma va rinormalizzata dopo,
    // altrimenti il taglio della pagina resta visibile come blocco a parte.
    return PlanExtraction(
      plan: normalizePlanDto(
        mergePlanDtos([for (final part in parts) part.plan]),
      ),
      usedFallback: parts.any((part) => part.usedFallback),
      rawResponse: [for (final part in parts) part.rawResponse].join('\n\n'),
    );
  }

  /// Fase 1: l'immagine diventa testo, senza structured output.
  ///
  /// Senza la grammatica dello schema addosso il modello si limita a copiare,
  /// che è il compito in cui è affidabile.
  Future<String> _transcribe(
    AiSelection selection, {
    required AiImage image,
    required int pageIndex,
    required int pageCount,
  }) async {
    final result = await _send(
      selection,
      system: transcriptionSystemPrompt,
      turns: [
        AiChatTurn.user(
          transcriptionUserText(pageIndex: pageIndex, pageCount: pageCount),
          image: image,
        ),
      ],
    );
    _guardTruncation(result, incomplete: 'La trascrizione della foto');
    return result.content;
  }

  /// Fase 2: dal testo al JSON, pipeline §6.2 con retry e fallback.
  ///
  /// Se la strutturazione fallisce due volte il blocco `freeText` conserva la
  /// trascrizione, non la risposta malformata: è il contenuto che serve
  /// davvero all'utente in editor (RNF-05).
  Future<PlanExtraction> _structure(
    AiSelection selection, {
    required String sourceText,
    String? userHint,
    int? pageIndex,
    int? pageCount,
  }) async {
    final turns = [
      AiChatTurn.user(
        extractionUserText(
          text: sourceText,
          userHint: userHint,
          pageIndex: pageIndex,
          pageCount: pageCount,
        ),
      ),
    ];
    Future<AiChatResult> ask() async {
      final result = await _send(
        selection,
        system: extractionSystemPrompt,
        turns: turns,
        structured: selection.model.supportsJsonSchema,
      );
      _guardTruncation(result, incomplete: 'La scheda');
      _guardDegenerate(result);
      return result;
    }

    PlanExtraction parsed(AiChatResult result) => PlanExtraction(
      plan: _parser.parse(result.content),
      usedFallback: false,
      rawResponse: result.content,
    );

    // Pipeline §6.2: prima chiamata → parse; errore di parsing → 1 retry con
    // messaggio correttivo; secondo fallimento → fallback freeText (RNF-05).
    final first = await ask();
    try {
      return parsed(first);
    } on PlanParseException catch (error) {
      turns
        ..add(AiChatTurn.assistant(first.content))
        ..add(AiChatTurn.user(retryUserText(error.message)));
    }
    final retry = await ask();
    try {
      return parsed(retry);
    } on PlanParseException {
      return PlanExtraction(
        plan: _parser.fallback(sourceText),
        usedFallback: true,
        rawResponse: retry.content,
      );
    }
  }

  /// [sendChat] con il ripiego S-02 di [postJson]: se il modello rifiuta lo
  /// structured output la stessa richiesta riparte una volta senza.
  Future<AiChatResult> _send(
    AiSelection selection, {
    required String system,
    required List<AiChatTurn> turns,
    bool structured = false,
  }) async {
    try {
      return await sendChat(
        selection: selection,
        system: system,
        turns: turns,
        structured: structured,
      );
    } on _StructuredOutputRejected {
      return sendChat(
        selection: selection,
        system: system,
        turns: turns,
        structured: false,
      );
    }
  }

  /// Una risposta troncata non va né riparsata né ritentata: il JSON
  /// incompleto fallisce il parse e il retry correttivo spinge il modello a
  /// rispondere con una scheda *più corta ma valida*, perdendo silenziosamente
  /// giorni ed esercizi. Meglio fermarsi e dirlo.
  void _guardTruncation(AiChatResult result, {required String incomplete}) {
    if (!result.isTruncated) return;
    throw AiResponseException(
      '$incomplete è stata troncata: supera il budget di output del modello. '
      'Riprova con una foto alla volta, o alza "maxOutputTokens" per il '
      'modello selezionato.',
    );
  }

  /// Sotto structured output capita che il modello si incastri ripetendo una
  /// cifra dentro un intero ("sets": 44444…): il JSON resta sintatticamente
  /// plausibile ma il numero non entra in un `int`, il parse fallisce e il
  /// retry ripiega su una scheda più corta. Riconosciuto qui, prima del retry.
  void _guardDegenerate(AiChatResult result) {
    if (!_degenerateDigits.hasMatch(result.content)) return;
    throw const AiResponseException(
      'Il modello ha prodotto una risposta anomala e la scheda risulterebbe '
      'incompleta. Riprova: se capita di nuovo, cambia modello nelle '
      'impostazioni AI.',
    );
  }

  /// Diagnostica di sviluppo: senza il motivo di terminazione e il conteggio
  /// token una scheda che arriva amputata è indistinguibile da una che il
  /// modello ha semplicemente letto male. Mai la API key, solo la risposta.
  @protected
  void logResponse({
    required String content,
    String? stopReason,
    Object? usage,
  }) {
    if (!kDebugMode) return;
    debugPrint(
      '[AI] ${id.value} stop=$stopReason usage=$usage '
      'chars=${content.length}',
    );
    debugPrint('[AI] risposta grezza:\n$content');
  }

  Options _authOptions(String apiKey) => Options(headers: authHeaders(apiKey));

  AiException _mapDioException(DioException e, {String? modelId}) {
    final status = e.response?.statusCode;
    if (status != null) {
      return exceptionForStatus(
        status,
        _errorMessage(e.response?.data) ?? 'Errore HTTP $status dal provider.',
        modelId: modelId,
      );
    }
    // Un timeout in ricezione non è un problema di rete: il modello sta
    // ancora generando (tipicamente perché è finito in un loop). Dirlo, o
    // l'utente cerca il guasto dalla parte sbagliata.
    if (e.type == DioExceptionType.receiveTimeout) {
      return AiNetworkException(
        'Il modello non ha completato la risposta entro il tempo massimo. '
        'Riprova con meno foto per volta, o cambia modello nelle '
        'impostazioni AI.',
        cause: e,
      );
    }
    return AiNetworkException(
      'Impossibile raggiungere $providerName: controlla la connessione.',
      cause: e,
    );
  }

  /// Il messaggio d'errore del corpo, nella forma che le tre API hanno in
  /// comune: `{"error": {"message": "…"}}`.
  static String? _errorMessage(Object? body) => switch (body) {
    {'error': {'message': final String message}} => message,
    _ => null,
  };
}
