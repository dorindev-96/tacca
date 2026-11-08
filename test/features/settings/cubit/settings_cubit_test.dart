import 'package:tacca/core/errors/ai_exception.dart';
import 'package:tacca/core/errors/ai_failure.dart';
import 'package:tacca/features/settings/cubit/settings_cubit.dart';
import 'package:tacca/features/settings/cubit/settings_state.dart';
import 'package:tacca/services/ai/ai_provider.dart';
import 'package:tacca/services/ai/ai_selection.dart';
import 'package:tacca/services/ai/model_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fakes.dart';

class _FakeAiProvider implements AiProvider {
  Object? testError;
  int testCalls = 0;

  @override
  Future<PlanExtraction> extractPlan({
    List<AiImage> images = const [],
    String? text,
    String? userHint,
  }) => throw UnimplementedError();

  @override
  Future<void> testConnection() async {
    testCalls++;
    final error = testError;
    if (error != null) throw error;
  }
}

const _catalog = AiModelCatalog(
  defaultProviderId: AiProviderId.openRouter,
  providers: [
    AiProviderOption(
      id: AiProviderId.openRouter,
      label: 'OpenRouter',
      defaultModelId: 'a/default',
      models: [
        AiModelOption(id: 'a/default', label: 'Default', supportsVision: true),
        AiModelOption(id: 'b/other', label: 'Altro'),
      ],
    ),
    AiProviderOption(
      id: AiProviderId.anthropic,
      label: 'Anthropic',
      defaultModelId: 'claude-opus-5',
      models: [
        AiModelOption(id: 'claude-opus-5', label: 'Opus', supportsVision: true),
        AiModelOption(id: 'claude-sonnet-5', label: 'Sonnet'),
      ],
    ),
  ],
);

void main() {
  late FakeSettingsRepository settings;
  late _FakeAiProvider provider;

  setUp(() {
    settings = FakeSettingsRepository();
    provider = _FakeAiProvider();
  });

  SettingsCubit buildCubit() => SettingsCubit(
    settings: settings,
    provider: provider,
    selection: AiSelectionResolver(settings: settings, catalog: _catalog),
  );

  test(
    'senza scelte: provider e modello di default, hasApiKey false',
    () async {
      final cubit = buildCubit();
      await pumpEventQueue();

      expect(cubit.state.isLoading, isFalse);
      expect(cubit.state.selectedProviderId, AiProviderId.openRouter);
      expect(cubit.state.hasApiKey, isFalse);
      expect(cubit.state.selectedModelId, 'a/default');
    },
  );

  test('un errore del secure storage diventa un fallimento, non un '
      '"nessuna key"', () async {
    settings.aiReadError = Exception('keystore bloccato');
    final cubit = buildCubit();
    await pumpEventQueue();

    expect(cubit.state.isLoading, isFalse);
    expect(cubit.state.failure, SettingsFailure.loadFailed);
  });

  test('un caricamento riuscito non ha fallimenti', () async {
    final cubit = buildCubit();
    await pumpEventQueue();

    expect(cubit.state.failure, isNull);
  });

  test('carica key e modello salvati', () async {
    settings
      ..apiKey = 'sk-or-x'
      ..modelId = 'b/other';
    final cubit = buildCubit();
    await pumpEventQueue();

    expect(cubit.state.hasApiKey, isTrue);
    expect(cubit.state.selectedModelId, 'b/other');
  });

  test('carica il provider salvato con le sue impostazioni', () async {
    settings
      ..providerId = 'anthropic'
      ..apiKeys['anthropic'] = 'sk-ant-x'
      ..modelIds['anthropic'] = 'claude-sonnet-5';
    final cubit = buildCubit();
    await pumpEventQueue();

    expect(cubit.state.selectedProviderId, AiProviderId.anthropic);
    expect(cubit.state.hasApiKey, isTrue);
    expect(cubit.state.selectedModelId, 'claude-sonnet-5');
    expect(cubit.selectedProvider.label, 'Anthropic');
  });

  test(
    'un modello salvato rimosso dal catalogo JSON torna al default',
    () async {
      settings.modelId = 'x/rimosso';
      final cubit = buildCubit();
      await pumpEventQueue();

      expect(cubit.state.selectedModelId, 'a/default');
    },
  );

  test('un provider salvato non più implementato torna al default', () async {
    settings.providerId = 'provider-sparito';
    final cubit = buildCubit();
    await pumpEventQueue();

    expect(cubit.state.selectedProviderId, AiProviderId.openRouter);
  });

  test('selectProvider persiste e mostra le impostazioni del nuovo '
      'provider, senza toccare quelle del vecchio', () async {
    settings
      ..apiKey = 'sk-or-x'
      ..modelId = 'b/other';
    final cubit = buildCubit();
    await pumpEventQueue();

    await cubit.selectProvider(AiProviderId.anthropic);

    expect(settings.providerId, 'anthropic');
    expect(cubit.state.selectedProviderId, AiProviderId.anthropic);
    // Anthropic non è ancora configurato: key assente, modello di default.
    expect(cubit.state.hasApiKey, isFalse);
    expect(cubit.state.selectedModelId, 'claude-opus-5');
    // La configurazione OpenRouter resta dov'era.
    expect(settings.apiKeys['openrouter'], 'sk-or-x');
    expect(settings.modelIds['openrouter'], 'b/other');
  });

  test('tornando al provider di prima si ritrova la sua key', () async {
    settings.apiKey = 'sk-or-x';
    final cubit = buildCubit();
    await pumpEventQueue();

    await cubit.selectProvider(AiProviderId.anthropic);
    await cubit.saveApiKey('sk-ant-nuova');
    await cubit.selectProvider(AiProviderId.openRouter);

    expect(settings.apiKeys['anthropic'], 'sk-ant-nuova');
    expect(cubit.state.hasApiKey, isTrue);
    expect(cubit.state.selectedModelId, 'a/default');
  });

  test('saveApiKey persiste (trim) sul provider scelto e azzera '
      'l\'esito del test', () async {
    final cubit = buildCubit();
    await pumpEventQueue();
    await cubit.selectProvider(AiProviderId.anthropic);

    await cubit.saveApiKey('  sk-ant-nuova  ');

    expect(settings.apiKeys['anthropic'], 'sk-ant-nuova');
    expect(settings.apiKeys['openrouter'], isNull);
    expect(cubit.state.hasApiKey, isTrue);
    expect(cubit.state.testStatus, AiConnectionTestStatus.idle);
  });

  test('removeApiKey cancella la key del provider scelto', () async {
    settings.apiKey = 'sk-or-x';
    final cubit = buildCubit();
    await pumpEventQueue();

    await cubit.removeApiKey();

    expect(settings.apiKeys['openrouter'], isNull);
    expect(cubit.state.hasApiKey, isFalse);
  });

  test('selectModel persiste la scelta sul provider scelto', () async {
    final cubit = buildCubit();
    await pumpEventQueue();

    await cubit.selectModel('b/other');

    expect(settings.modelIds['openrouter'], 'b/other');
    expect(cubit.state.selectedModelId, 'b/other');
  });

  test('test connessione riuscito', () async {
    settings.apiKey = 'sk-or-x';
    final cubit = buildCubit();
    await pumpEventQueue();

    await cubit.testConnection();

    expect(provider.testCalls, 1);
    expect(cubit.state.testStatus, AiConnectionTestStatus.success);
  });

  test('key invalida: fallimento con messaggio parlante (§9)', () async {
    settings.apiKey = 'sk-or-x';
    provider.testError = const AiAuthException('API key non valida.');
    final cubit = buildCubit();
    await pumpEventQueue();

    await cubit.testConnection();

    expect(cubit.state.testStatus, AiConnectionTestStatus.failure);
    expect(cubit.state.testFailure, AiFailure.auth);
  });
}
