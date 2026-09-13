import 'dart:convert';
import 'dart:typed_data';

import 'package:tacca/core/errors/ai_exception.dart';
import 'package:tacca/data/entities/block.dart';
import 'package:tacca/services/ai/ai_provider.dart';
import 'package:tacca/services/ai/ai_selection.dart';
import 'package:tacca/services/ai/model_catalog.dart';
import 'package:tacca/services/ai/providers/open_router_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/fakes.dart';

class _MockAdapter extends Mock implements HttpClientAdapter {}

const _catalog = AiModelCatalog(
  defaultProviderId: AiProviderId.openRouter,
  providers: [
    AiProviderOption(
      id: AiProviderId.openRouter,
      label: 'OpenRouter',
      defaultModelId: 'schema/model',
      models: [
        AiModelOption(
          id: 'schema/model',
          label: 'Con schema',
          supportsVision: true,
          supportsJsonSchema: true,
          maxOutputTokens: 12345,
        ),
        AiModelOption(id: 'plain/model', label: 'Senza schema'),
        AiModelOption(
          id: 'reasoning/model',
          label: 'Con reasoning da disattivare',
          disableReasoning: true,
        ),
        AiModelOption(id: 'qualcuno/modello:free', label: 'Gratuito'),
      ],
    ),
  ],
);

const _validPlanJson =
    '{"name":"Scheda","days":[{"label":"A","blocks":[{"type":"standard",'
    '"exercises":[{"name":"Panca","sets":4,"reps":"8"}]}]}]}';

/// Corpo di risposta OpenAI-compatible con [content] come testo del modello.
String _completionBody(String content, {String finishReason = 'stop'}) =>
    jsonEncode({
      'choices': [
        {
          'message': {'role': 'assistant', 'content': content},
          'finish_reason': finishReason,
        },
      ],
    });

void main() {
  late _MockAdapter adapter;
  late FakeSettingsRepository settings;
  late OpenRouterProvider provider;

  /// Richieste catturate dall'adapter, nell'ordine di invio.
  late List<RequestOptions> requests;

  setUpAll(() {
    registerFallbackValue(RequestOptions(path: '/'));
  });

  setUp(() {
    adapter = _MockAdapter();
    settings = FakeSettingsRepository(apiKey: 'sk-or-test');
    requests = [];
    final dio = Dio(BaseOptions(baseUrl: 'https://openrouter.ai/api/v1'))
      ..httpClientAdapter = adapter;
    provider = OpenRouterProvider(
      selection: AiSelectionResolver(settings: settings, catalog: _catalog),
      dio: dio,
    );
  });

  /// Accoda le risposte HTTP che l'adapter servirà in sequenza.
  void enqueueResponses(List<ResponseBody> responses) {
    var index = 0;
    when(() => adapter.fetch(any(), any(), any())).thenAnswer((invocation) {
      requests.add(invocation.positionalArguments.first as RequestOptions);
      return Future.value(responses[index++]);
    });
  }

  ResponseBody ok(String content, {String finishReason = 'stop'}) =>
      ResponseBody.fromString(
        _completionBody(content, finishReason: finishReason),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );

  ResponseBody status(int code, {String body = '{}'}) =>
      ResponseBody.fromString(
        body,
        code,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );

  group('extractPlan', () {
    test(
      'risposta valida al primo colpo, con response_format json_schema',
      () async {
        enqueueResponses([ok(_validPlanJson)]);

        final extraction = await provider.extractPlan(text: 'Panca 4x8');

        expect(extraction.usedFallback, isFalse);
        expect(extraction.plan.name, 'Scheda');
        expect(requests, hasLength(1));

        final body = requests.single.data as Map<String, dynamic>;
        expect(body['model'], 'schema/model');
        expect(body['response_format'], isNotNull);
        expect(body['max_tokens'], 12345);
        expect(requests.single.headers['Authorization'], 'Bearer sk-or-test');
      },
    );

    test(
      'max_tokens ricade sul default quando il catalogo non lo indica',
      () async {
        settings.modelId = 'plain/model';
        enqueueResponses([ok('```json\n$_validPlanJson\n```')]);

        await provider.extractPlan(text: 'Panca 4x8');

        final body = requests.single.data as Map<String, dynamic>;
        expect(body['max_tokens'], AiModelOption.defaultMaxOutputTokens);
      },
    );

    test(
      'un modello salvato che non è più nel catalogo ricade sul default',
      () async {
        settings.modelId = 'sparito/dal-catalogo';
        enqueueResponses([ok(_validPlanJson)]);

        await provider.extractPlan(text: 'Panca 4x8');

        final body = requests.single.data as Map<String, dynamic>;
        expect(body['model'], 'schema/model');
      },
    );

    test(
      'disableReasoning nel catalogo aggiunge reasoning: {effort: none}',
      () async {
        settings.modelId = 'reasoning/model';
        enqueueResponses([ok(_validPlanJson)]);

        await provider.extractPlan(text: 'Panca 4x8');

        final body = requests.single.data as Map<String, dynamic>;
        expect(body['reasoning'], {'effort': 'none'});
      },
    );

    test(
      'senza disableReasoning nel catalogo, niente campo reasoning',
      () async {
        enqueueResponses([ok(_validPlanJson)]);

        await provider.extractPlan(text: 'Panca 4x8');

        final body = requests.single.data as Map<String, dynamic>;
        expect(body.containsKey('reasoning'), isFalse);
      },
    );

    test('risposta troncata (finish_reason: length) → errore esplicito, '
        'nessun retry che accorcia la scheda', () async {
      enqueueResponses([ok(_validPlanJson, finishReason: 'length')]);

      await expectLater(
        provider.extractPlan(text: 'Scheda lunga'),
        throwsA(
          isA<AiResponseException>().having(
            (e) => e.message,
            'message',
            contains('troncata'),
          ),
        ),
      );
      expect(requests, hasLength(1));
    });

    test(
      'il modello senza supporto schema usa la richiesta prompt-based',
      () async {
        settings.modelId = 'plain/model';
        enqueueResponses([ok('```json\n$_validPlanJson\n```')]);

        final extraction = await provider.extractPlan(text: 'Panca 4x8');

        expect(extraction.plan.name, 'Scheda');
        final body = requests.single.data as Map<String, dynamic>;
        expect(body['model'], 'plain/model');
        expect(body.containsKey('response_format'), isFalse);
      },
    );

    test(
      'foto → trascrizione senza schema, poi strutturazione del testo',
      () async {
        enqueueResponses([ok('Panca 4x8'), ok(_validPlanJson)]);

        final extraction = await provider.extractPlan(
          images: [
            AiImage(Uint8List.fromList([1, 2, 3])),
          ],
        );

        expect(extraction.plan.name, 'Scheda');
        expect(requests, hasLength(2));

        // Fase 1: l'immagine viaggia come data URL, senza structured output.
        final transcription = requests[0].data as Map<String, dynamic>;
        final userContent =
            (transcription['messages'] as List)[1]['content'] as List<dynamic>;
        final imagePart = userContent[1] as Map<String, dynamic>;
        expect(imagePart['type'], 'image_url');
        expect(
          imagePart['image_url']['url'],
          'data:image/jpeg;base64,${base64Encode([1, 2, 3])}',
        );
        expect(transcription.containsKey('response_format'), isFalse);

        // Fase 2: solo testo, con lo schema, e nessuna immagine allegata.
        final structuring = requests[1].data as Map<String, dynamic>;
        expect(structuring.containsKey('response_format'), isTrue);
        expect(
          (structuring['messages'] as List)[1]['content'],
          contains('Panca 4x8'),
        );
      },
    );

    test(
      'più immagini → due fasi per pagina, giorni fusi in una scheda',
      () async {
        const page1 =
            '{"name":"Scheda","days":[{"label":"Day 1","blocks":[{"type":'
            '"standard","exercises":[{"name":"Lat machine"}]}]}]}';
        const page2 =
            '{"name":"Scheda","days":[{"label":"Day 1","blocks":[{"type":'
            '"standard","exercises":[{"name":"Pulley"}]}]},{"label":"Day 2",'
            '"blocks":[{"type":"standard","exercises":[{"name":"Squat"}]}]}]}';
        enqueueResponses([
          ok('testo pagina uno'),
          ok(page1),
          ok('testo pagina due'),
          ok(page2),
        ]);

        final extraction = await provider.extractPlan(
          images: [
            AiImage(Uint8List.fromList([1])),
            AiImage(Uint8List.fromList([2])),
          ],
        );

        expect(requests, hasLength(4));
        // Ogni trascrizione porta una sola immagine e sa che pagina è.
        for (final request in [requests[0], requests[2]]) {
          final content =
              (request.data as Map<String, dynamic>)['messages'][1]['content']
                  as List<dynamic>;
          expect(
            content.whereType<Map>().where((p) => p['type'] == 'image_url'),
            hasLength(1),
          );
        }
        expect(
          (requests[2].data
              as Map<String, dynamic>)['messages'][1]['content'][0]['text'],
          contains('page 2 of 2'),
        );
        // La strutturazione lavora sulla trascrizione della sua pagina.
        expect(
          (requests[3].data as Map<String, dynamic>)['messages'][1]['content'],
          contains('testo pagina due'),
        );

        // Il giorno che prosegue sulla seconda pagina non viene duplicato, e
        // il taglio fra le pagine non lascia due blocchi standard di fila.
        expect(extraction.plan.days, hasLength(2));
        final firstDayBlocks = extraction.plan.days.first.blocks;
        expect(firstDayBlocks, hasLength(1));
        expect(
          [for (final e in firstDayBlocks.single.exercises) e.name],
          ['Lat machine', 'Pulley'],
        );
        expect(extraction.plan.days.last.label, 'Day 2');
      },
    );

    test(
      'cifra ripetuta all\'infinito → errore, non una scheda accorciata',
      () async {
        final degenerate =
            '{"name":"Scheda","days":[{"label":"A","blocks":[{"type":"standard",'
            '"exercises":[{"name":"Lat machine","sets":${'4' * 60}}]}]}]}';
        enqueueResponses([ok(degenerate)]);

        await expectLater(
          provider.extractPlan(text: 'Lat machine 10x4'),
          throwsA(
            isA<AiResponseException>().having(
              (e) => e.message,
              'message',
              contains('anomala'),
            ),
          ),
        );
        // Nessun retry: ritentare qui è come il modello restituisse meno righe.
        expect(requests, hasLength(1));
      },
    );

    test(
      'parsing fallito → 1 retry con messaggio correttivo → successo (§6.2)',
      () async {
        enqueueResponses([ok('non è JSON'), ok(_validPlanJson)]);

        final extraction = await provider.extractPlan(text: 'Panca');

        expect(extraction.usedFallback, isFalse);
        expect(extraction.plan.name, 'Scheda');
        expect(requests, hasLength(2));

        // La seconda richiesta accoda la risposta errata e la correzione.
        final retryMessages =
            (requests[1].data as Map<String, dynamic>)['messages'] as List;
        expect(retryMessages, hasLength(4));
        expect(retryMessages[2]['role'], 'assistant');
        expect(retryMessages[2]['content'], 'non è JSON');
        expect(retryMessages[3]['role'], 'user');
        expect(retryMessages[3]['content'], contains('JSON'));
      },
    );

    test(
      'doppio fallimento → fallback freeText con il testo di partenza',
      () async {
        enqueueResponses([ok('boh'), ok('ancora niente JSON')]);

        final extraction = await provider.extractPlan(text: 'Panca 4x8');

        expect(extraction.usedFallback, isTrue);
        final block = extraction.plan.days.single.blocks.single;
        expect(block.type, BlockType.freeText.name);
        // In editor serve la scheda dell'utente, non il tentativo fallito.
        expect(block.content, 'Panca 4x8');
        expect(extraction.rawResponse, 'ancora niente JSON');
      },
    );

    test(
      'senza API key → AiConfigurationException, nessuna richiesta',
      () async {
        settings.apiKey = null;

        await expectLater(
          provider.extractPlan(text: 'Panca'),
          throwsA(isA<AiConfigurationException>()),
        );
        verifyNever(() => adapter.fetch(any(), any(), any()));
      },
    );

    test('401 → AiAuthException (key invalida)', () async {
      enqueueResponses([
        status(401, body: '{"error":{"message":"Invalid key"}}'),
      ]);

      await expectLater(
        provider.extractPlan(text: 'Panca'),
        throwsA(
          isA<AiAuthException>().having(
            (e) => e.message,
            'message',
            contains('Invalid key'),
          ),
        ),
      );
    });

    test('402/429 → AiQuotaException (crediti o rate limit)', () async {
      enqueueResponses([status(429)]);
      await expectLater(
        provider.extractPlan(text: 'Panca'),
        throwsA(isA<AiQuotaException>()),
      );
    });

    test('429 sul piano gratuito → il messaggio dice che il gratis è '
        'finito, non "rate limit"', () async {
      enqueueResponses([
        status(
          429,
          body: jsonEncode({
            'error': {
              'code': 429,
              'message':
                  'Rate limit exceeded: free-models-per-day. Add 10 credits '
                  'to unlock 1000 free model requests per day',
            },
          }),
        ),
      ]);

      await expectLater(
        provider.extractPlan(text: 'Panca'),
        throwsA(
          isA<AiQuotaException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('richieste gratuite'),
              contains('utilizzo gratis è finito'),
              contains('impostazioni AI'),
            ),
          ),
        ),
      );
    });

    test('429 su un modello ":free" con messaggio generico → riconosciuto '
        'lo stesso come gratis esaurito', () async {
      settings.modelId = 'qualcuno/modello:free';
      enqueueResponses([
        status(
          429,
          body: jsonEncode({
            'error': {'code': 429, 'message': 'Too many requests'},
          }),
        ),
      ]);

      await expectLater(
        provider.extractPlan(text: 'Panca'),
        throwsA(
          isA<AiQuotaException>().having(
            (e) => e.message,
            'message',
            contains('utilizzo gratis è finito'),
          ),
        ),
      );
    });

    test('429 su un modello a pagamento → rate limit temporaneo', () async {
      enqueueResponses([
        status(
          429,
          body: jsonEncode({
            'error': {'code': 429, 'message': 'Too many requests'},
          }),
        ),
      ]);

      await expectLater(
        provider.extractPlan(text: 'Panca'),
        throwsA(
          isA<AiQuotaException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('aspetta qualche istante'),
              isNot(contains('gratis')),
            ),
          ),
        ),
      );
    });

    test('402 → credito esaurito, con il rimedio', () async {
      enqueueResponses([
        status(
          402,
          body: jsonEncode({
            'error': {
              'code': 402,
              'message':
                  'This request requires more credits, or fewer max_tokens.',
            },
          }),
        ),
      ]);

      await expectLater(
        provider.extractPlan(text: 'Panca'),
        throwsA(
          isA<AiQuotaException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('Credito OpenRouter esaurito'),
              contains('openrouter.ai/credits'),
            ),
          ),
        ),
      );
    });

    test('errore di quota dentro un 200 → stesso messaggio parlante', () async {
      enqueueResponses([
        ResponseBody.fromString(
          jsonEncode({
            'error': {
              'code': 429,
              'message': 'Rate limit exceeded: free-models-per-day',
            },
          }),
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
          },
        ),
      ]);

      await expectLater(
        provider.extractPlan(text: 'Panca'),
        throwsA(
          isA<AiQuotaException>().having(
            (e) => e.message,
            'message',
            contains('utilizzo gratis è finito'),
          ),
        ),
      );
    });

    test('errore di rete → AiNetworkException', () async {
      when(() => adapter.fetch(any(), any(), any())).thenAnswer(
        (invocation) => throw DioException.connectionError(
          requestOptions:
              invocation.positionalArguments.first as RequestOptions,
          reason: 'offline',
        ),
      );

      await expectLater(
        provider.extractPlan(text: 'Panca'),
        throwsA(isA<AiNetworkException>()),
      );
    });

    test('response_format rifiutato dal modello (400) → ritenta prompt-based '
        '(S-02)', () async {
      enqueueResponses([
        status(
          400,
          body: '{"error":{"message":"response_format unsupported"}}',
        ),
        ok('```json\n$_validPlanJson\n```'),
      ]);

      final extraction = await provider.extractPlan(text: 'Panca');

      expect(extraction.plan.name, 'Scheda');
      expect(requests, hasLength(2));
      final first = requests[0].data as Map<String, dynamic>;
      final second = requests[1].data as Map<String, dynamic>;
      expect(first.containsKey('response_format'), isTrue);
      expect(second.containsKey('response_format'), isFalse);
    });
  });

  group('testConnection', () {
    test('completa con una key valida', () async {
      enqueueResponses([status(200, body: '{"data":{"label":"test"}}')]);
      await provider.testConnection();
      expect(requests.single.path, contains('/key'));
      expect(requests.single.method, 'GET');
    });

    test('401 → AiAuthException', () async {
      enqueueResponses([status(401)]);
      await expectLater(
        provider.testConnection(),
        throwsA(isA<AiAuthException>()),
      );
    });
  });
}
