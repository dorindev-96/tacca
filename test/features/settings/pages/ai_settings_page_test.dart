import 'package:tacca/features/settings/cubit/settings_cubit.dart';
import 'package:tacca/features/settings/pages/ai_settings_page.dart';
import 'package:tacca/l10n/app_localizations.dart';
import 'package:tacca/services/ai/ai_provider.dart';
import 'package:tacca/services/ai/ai_selection.dart';
import 'package:tacca/services/ai/model_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fakes.dart';

class _FakeAiProvider implements AiProvider {
  @override
  Future<PlanExtraction> extractPlan({
    List<AiImage> images = const [],
    String? text,
    String? userHint,
  }) => throw UnimplementedError();

  @override
  Future<void> testConnection() async {}
}

const _catalog = AiModelCatalog(
  defaultProviderId: AiProviderId.openRouter,
  providers: [
    AiProviderOption(
      id: AiProviderId.openRouter,
      label: 'OpenRouter',
      keyHint: 'sk-or-…',
      defaultModelId: 'deepseek/flash',
      models: [
        AiModelOption(id: 'deepseek/flash', label: 'DeepSeek Flash'),
        AiModelOption(id: 'google/gemini', label: 'Gemini'),
      ],
    ),
    AiProviderOption(
      id: AiProviderId.anthropic,
      label: 'Anthropic',
      keyHint: 'sk-ant-…',
      defaultModelId: 'claude-opus-5',
      models: [
        AiModelOption(id: 'claude-opus-5', label: 'Claude Opus 5'),
        AiModelOption(id: 'claude-sonnet-5', label: 'Claude Sonnet 5'),
      ],
    ),
  ],
);

void main() {
  late FakeSettingsRepository settings;

  setUp(() {
    settings = FakeSettingsRepository();
  });

  Future<void> pumpPage(WidgetTester tester) async {
    // Con il campo key aperto la pagina supera gli 800x600 della finestra di
    // default e il selettore del modello resta sotto il bordo: i tap non lo
    // raggiungerebbero.
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // I test verificano le stringhe italiane: senza fissare la lingua
        // la locale di test (en_US) non è fra quelle tradotte e Flutter
        // ripiegherebbe sulla prima in ordine alfabetico, il tedesco.
        locale: const Locale('it'),
        home: BlocProvider(
          create: (context) => SettingsCubit(
            settings: settings,
            provider: _FakeAiProvider(),
            selection: AiSelectionResolver(
              settings: settings,
              catalog: _catalog,
            ),
          ),
          child: const AiSettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Sceglie [label] dalla tendina che sta mostrando [current].
  Future<void> selectFromDropdown(
    WidgetTester tester, {
    required String current,
    required String label,
  }) async {
    await tester.tap(find.text(current).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets('mostra provider e modelli del catalogo, e l\'avviso privacy', (
    tester,
  ) async {
    await pumpPage(tester);

    expect(find.text('OpenRouter'), findsOneWidget);
    expect(find.text('DeepSeek Flash'), findsOneWidget);
    expect(find.text('API key OpenRouter'), findsOneWidget);
    expect(
      find.textContaining('vengono trasmessi a OpenRouter'),
      findsOneWidget,
    );
    // Il provider non selezionato non compare finché non si apre la tendina.
    expect(find.text('Anthropic'), findsNothing);
  });

  testWidgets('scegliere Anthropic cambia modelli, etichetta e placeholder '
      'della key', (tester) async {
    await pumpPage(tester);

    await selectFromDropdown(tester, current: 'OpenRouter', label: 'Anthropic');

    expect(settings.providerId, 'anthropic');
    expect(find.text('API key Anthropic'), findsOneWidget);
    expect(find.text('Claude Opus 5'), findsOneWidget);
    // I modelli dell'altro provider non sono più selezionabili.
    expect(find.text('DeepSeek Flash'), findsNothing);
    expect(find.text('sk-ant-…'), findsOneWidget);
  });

  testWidgets('il modello scelto si salva sul provider selezionato', (
    tester,
  ) async {
    await pumpPage(tester);

    await selectFromDropdown(tester, current: 'OpenRouter', label: 'Anthropic');
    await selectFromDropdown(
      tester,
      current: 'Claude Opus 5',
      label: 'Claude Sonnet 5',
    );

    expect(settings.modelIds['anthropic'], 'claude-sonnet-5');
    expect(settings.modelIds['openrouter'], isNull);
  });

  testWidgets('la key salvata di un provider non si vede sull\'altro', (
    tester,
  ) async {
    settings.apiKeys['openrouter'] = 'sk-or-x';
    await pumpPage(tester);

    expect(
      find.text('API key salvata nel portachiavi del dispositivo.'),
      findsOneWidget,
    );

    await selectFromDropdown(tester, current: 'OpenRouter', label: 'Anthropic');

    // Anthropic non è configurato: torna il campo di inserimento.
    expect(find.text('sk-ant-…'), findsOneWidget);
    expect(
      find.text(
        'Le funzioni AI sono disabilitate finché non salvi una API key.',
      ),
      findsOneWidget,
    );
  });
}
