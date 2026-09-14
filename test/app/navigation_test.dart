import 'package:tacca/app/router.dart';
import 'package:tacca/data/entities/block.dart';
import 'package:tacca/data/entities/exercise.dart';
import 'package:tacca/data/entities/workout_day.dart';
import 'package:tacca/data/entities/workout_log.dart';
import 'package:tacca/data/entities/workout_plan.dart';
import 'package:tacca/data/repositories/plan_repository.dart';
import 'package:tacca/data/repositories/settings_repository.dart';
import 'package:tacca/data/repositories/workout_log_repository.dart';
import 'package:tacca/features/history/cubit/history_cubit.dart';
import 'package:tacca/features/plans/cubit/plans_cubit.dart';
import 'package:tacca/features/settings/cubit/locale_cubit.dart';
import 'package:tacca/features/settings/cubit/theme_mode_cubit.dart';
import 'package:tacca/features/workout/cubit/active_session_cubit.dart';
import 'package:tacca/l10n/app_localizations.dart';
import 'package:tacca/services/ai/ai_provider.dart';
import 'package:tacca/services/ai/ai_selection.dart';
import 'package:tacca/services/ai/model_catalog.dart';
import 'package:tacca/services/feedback/session_feedback.dart';
import 'package:tacca/services/live_session/live_session_controller.dart';
import 'package:tacca/services/notifications/session_notifier.dart';
import 'package:tacca/services/timer/timer_engine.dart';
import 'package:tacca/services/wakelock/screen_wake.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart' show GoRouter;
import 'package:intl/date_symbol_data_local.dart';

import '../support/fakes.dart';

/// Catalogo minimo: alle impostazioni AI serve un provider da mostrare.
const _catalog = AiModelCatalog(
  defaultProviderId: AiProviderId.openRouter,
  providers: [
    AiProviderOption(
      id: AiProviderId.openRouter,
      label: 'OpenRouter',
      keyHint: 'sk-or-…',
      defaultModelId: 'deepseek/flash',
      models: [AiModelOption(id: 'deepseek/flash', label: 'DeepSeek Flash')],
    ),
  ],
);

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

// Smoke test della navigazione a 3 tab. Monta shell + router con repository
// fake in memoria: le pagine dipendono dai Cubit di feature, ma il test resta
// senza ObjectBox e senza plugin.
void main() {
  // Le date localizzate passano da DateFormat, che vuole i simboli caricati
  // (in produzione lo fa `main()`).
  setUpAll(() => initializeDateFormatting('it'));

  /// Scheda a un giorno, quanto basta per aprire una sessione.
  WorkoutPlan seedPlan(FakePlanRepository plans) {
    final now = DateTime(2026, 1, 1);
    final plan = WorkoutPlan(
      name: 'Push Pull Legs',
      createdAt: now,
      updatedAt: now,
    )..id = 1;
    plan.days.add(WorkoutDay(label: 'Giorno A')..id = 1);
    plans.add(plan);
    return plan;
  }

  Future<GoRouter> pumpApp(
    WidgetTester tester, {
    required FakePlanRepository plans,
    required FakeWorkoutLogRepository logs,
  }) async {
    final settings = FakeSettingsRepository();
    final router = createRouter();
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<PlanRepository>.value(value: plans),
          RepositoryProvider<WorkoutLogRepository>.value(value: logs),
          RepositoryProvider<SettingsRepository>.value(value: settings),
          RepositoryProvider<AiProvider>.value(value: _FakeAiProvider()),
          RepositoryProvider<AiSelectionResolver>.value(
            value: AiSelectionResolver(settings: settings, catalog: _catalog),
          ),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider<PlansCubit>(
              create: (context) => PlansCubit(repository: plans),
            ),
            BlocProvider<HistoryCubit>(
              create: (context) => HistoryCubit(repository: logs),
            ),
            BlocProvider<ActiveSessionCubit>(
              create: (context) => ActiveSessionCubit(repository: logs),
            ),
            BlocProvider<LocaleCubit>(
              create: (context) => LocaleCubit(settings: settings),
            ),
            BlocProvider<ThemeModeCubit>(
              create: (context) => ThemeModeCubit(settings: settings),
            ),
          ],
          child: MaterialApp.router(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            // I test verificano le stringhe italiane: senza fissare la lingua
            // la locale di test (en_US) non è fra quelle tradotte e Flutter
            // ripiegherebbe sulla prima in ordine alfabetico, il tedesco.
            locale: const Locale('it'),
            routerConfig: router,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('mostra tre destinazioni e parte dalle Schede', (tester) async {
    await pumpApp(
      tester,
      plans: FakePlanRepository(),
      logs: FakeWorkoutLogRepository(),
    );

    // Le destinazioni della tab bar flottante: solo quella attiva porta
    // l'etichetta a schermo, quindi si cercano per chiave.
    expect(find.byKey(const ValueKey('home-tab-Schede')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-tab-Storico')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-tab-Impostazioni')), findsOneWidget);
    // Ramo iniziale: archivio schede.
    expect(find.text('Le mie schede'), findsOneWidget);
    expect(
      find.text('Nessuna scheda. Creane una per iniziare.'),
      findsOneWidget,
    );
  });

  testWidgets('naviga tra Schede, Storico e Impostazioni', (tester) async {
    await pumpApp(
      tester,
      plans: FakePlanRepository(),
      logs: FakeWorkoutLogRepository(),
    );

    // → Storico.
    await tester.tap(find.byKey(const ValueKey('home-tab-Storico')));
    await tester.pumpAndSettle();
    expect(find.text('Nessun allenamento registrato.'), findsOneWidget);

    // → Impostazioni.
    await tester.tap(find.byKey(const ValueKey('home-tab-Impostazioni')));
    await tester.pumpAndSettle();
    expect(find.text('Intelligenza artificiale'), findsOneWidget);

    // → di nuovo Schede.
    await tester.tap(find.byKey(const ValueKey('home-tab-Schede')));
    await tester.pumpAndSettle();
    expect(
      find.text('Nessuna scheda. Creane una per iniziare.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'le impostazioni AI si aprono anche da una pagina fuori dalla shell',
    (tester) async {
      final router = await pumpApp(
        tester,
        plans: FakePlanRepository(),
        logs: FakeWorkoutLogRepository(),
      );

      // Il percorso dell'import senza key: si è già su una pagina di primo
      // livello e da lì si va alle impostazioni. Finché `/settings/ai` era
      // un ramo della shell, questa push ricostruiva la shell come seconda
      // pagina del navigator radice e il framework si fermava su chiavi di
      // pagina duplicate.
      router.push('/plans/new');
      await tester.pumpAndSettle();
      router.push('/settings/ai');
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Configurazione AI'), findsOneWidget);

      // E si torna indietro sulla pagina da cui si era partiti, non nella
      // shell.
      router.pop();
      await tester.pumpAndSettle();
      expect(find.text('Nuova scheda'), findsWidgets);
    },
  );

  testWidgets('all\'avvio propone di riprendere la sessione interrotta', (
    tester,
  ) async {
    final logs = FakeWorkoutLogRepository();
    logs.saveLog(
      WorkoutLog.start(
        startedAt: DateTime(2026, 8, 14, 19, 30),
        planNameSnapshot: 'Push Pull Legs',
        dayLabelSnapshot: 'Giorno A',
      ),
    );

    await pumpApp(tester, plans: FakePlanRepository(), logs: logs);

    expect(find.text('Riprendere l\'allenamento?'), findsOneWidget);
    expect(find.textContaining('Push Pull Legs'), findsWidgets);

    // "Più tardi": la sessione resta in corso e la proposta non si ripete —
    // ma resta la card in cima all'archivio, che è il punto di rientro.
    await tester.tap(find.text('Più tardi'));
    await tester.pumpAndSettle();
    expect(find.text('Riprendere l\'allenamento?'), findsNothing);
    expect(find.text('Allenamento in corso'), findsOneWidget);
  });

  testWidgets('la proposta aspetta la shell montata dal gate legale', (
    tester,
  ) async {
    final plans = FakePlanRepository();
    final logs = FakeWorkoutLogRepository();
    logs.saveLog(
      WorkoutLog.start(
        startedAt: DateTime(2026, 8, 14, 19, 30),
        planNameSnapshot: 'Push Pull Legs',
        dayLabelSnapshot: 'Giorno A',
      ),
    );
    final router = createRouter();

    // Come il gate legale: finché la manleva non è accettata il router — e
    // quindi la shell — non esiste. Il Cubit invece sì (`lazy: false`), e ha
    // già letto il database: la proposta non deve andare persa per strada.
    final accepted = ValueNotifier(false);
    addTearDown(accepted.dispose);

    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<PlanRepository>.value(value: plans),
          RepositoryProvider<WorkoutLogRepository>.value(value: logs),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider<PlansCubit>(
              create: (context) => PlansCubit(repository: plans),
            ),
            BlocProvider<HistoryCubit>(
              create: (context) => HistoryCubit(repository: logs),
            ),
            BlocProvider<ActiveSessionCubit>(
              lazy: false,
              create: (context) => ActiveSessionCubit(repository: logs),
            ),
          ],
          child: ValueListenableBuilder<bool>(
            valueListenable: accepted,
            builder: (context, open, child) => open
                ? MaterialApp.router(
                    localizationsDelegates:
                        AppLocalizations.localizationsDelegates,
                    supportedLocales: AppLocalizations.supportedLocales,
                    // I test verificano le stringhe italiane: senza fissare la lingua
                    // la locale di test (en_US) non è fra quelle tradotte e Flutter
                    // ripiegherebbe sulla prima in ordine alfabetico, il tedesco.
                    locale: const Locale('it'),
                    routerConfig: router,
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Riprendere l\'allenamento?'), findsNothing);

    accepted.value = true;
    await tester.pumpAndSettle();

    expect(find.text('Riprendere l\'allenamento?'), findsOneWidget);

    // Il dialog va chiuso prima della fine del test: lasciarlo aperto lascia
    // appesa anche l'attesa che lo ha aperto.
    await tester.tap(find.text('Più tardi'));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'una sessione aperta ad app avviata compare nell\'archivio senza riavvio',
    (tester) async {
      final plans = FakePlanRepository();
      final logs = FakeWorkoutLogRepository();
      final plan = seedPlan(plans);

      await pumpApp(tester, plans: plans, logs: logs);

      // Nessuna sessione: nessuna card, e nessuna proposta di ripresa.
      expect(find.text('Allenamento in corso'), findsNothing);
      expect(find.text('Riprendere l\'allenamento?'), findsNothing);

      // La sessione nasce mentre l'app è viva: prima di questo, l'archivio se
      // ne accorgeva solo chiudendo e riaprendo l'app.
      logs.startSession(plan: plan, day: plan.days.first);
      await tester.pumpAndSettle();

      expect(find.text('Allenamento in corso'), findsOneWidget);
      // Il nome della scheda è anche nella lista sotto: a distinguere la card
      // è il giorno in corso.
      expect(find.text('Giorno A'), findsOneWidget);
      // La proposta all'avvio riguarda solo la sessione trovata aperta
      // all'apertura dell'app: questa l'ha appena aperta l'utente.
      expect(find.text('Riprendere l\'allenamento?'), findsNothing);
    },
  );

  testWidgets('apre la modalità allenamento da /workout/new senza eccezioni', (
    tester,
  ) async {
    // La modalità allenamento riempie lo schermo: finestra ampia perché
    // testata e lista ci stiano senza overflow di layout.
    tester.view.physicalSize = const Size(1400, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final plans = FakePlanRepository();
    final logs = FakeWorkoutLogRepository();
    final now = DateTime(2026, 1, 1);
    final plan = WorkoutPlan(
      name: 'Push Pull Legs',
      createdAt: now,
      updatedAt: now,
    )..id = 1;
    final day = WorkoutDay(label: 'Giorno A')..id = 1;
    final block = Block.ofType(BlockType.standard)..id = 1;
    block.exercises.add(
      Exercise(name: 'Panca piana', sets: 3, reps: '8')..id = 1,
    );
    day.blocks.add(block);
    plan.days.add(day);
    plans.add(plan);

    final timerEngine = TimerEngine(
      now: () => now,
      tickInterval: const Duration(minutes: 30),
    );
    addTearDown(timerEngine.dispose);
    final router = createRouter();

    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<PlanRepository>.value(value: plans),
          RepositoryProvider<WorkoutLogRepository>.value(value: logs),
          RepositoryProvider<TimerEngine>.value(value: timerEngine),
          RepositoryProvider<SessionFeedback>.value(
            value: RecordingSessionFeedback(),
          ),
          RepositoryProvider<SessionNotifier>.value(
            value: RecordingSessionNotifier(),
          ),
          RepositoryProvider<ScreenWake>.value(value: RecordingScreenWake()),
          RepositoryProvider<LiveSessionController>.value(
            value: RecordingLiveSession(),
          ),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider<PlansCubit>(
              create: (context) => PlansCubit(repository: plans),
            ),
            BlocProvider<HistoryCubit>(
              create: (context) => HistoryCubit(repository: logs),
            ),
            BlocProvider<ActiveSessionCubit>(
              create: (context) => ActiveSessionCubit(repository: logs),
            ),
            BlocProvider<LocaleCubit>(
              create: (context) =>
                  LocaleCubit(settings: FakeSettingsRepository()),
            ),
            BlocProvider<ThemeModeCubit>(
              create: (context) =>
                  ThemeModeCubit(settings: FakeSettingsRepository()),
            ),
          ],
          child: MaterialApp.router(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            // I test verificano le stringhe italiane: senza fissare la lingua
            // la locale di test (en_US) non è fra quelle tradotte e Flutter
            // ripiegherebbe sulla prima in ordine alfabetico, il tedesco.
            locale: const Locale('it'),
            routerConfig: router,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Costruire questa route risolveva le etichette della schermata di blocco
    // (ARB) dentro il `create:` del BlocProvider: un lookup che ascolta un
    // InheritedWidget in un lifecycle che non verrà più richiamato → assertion.
    router.go('/workout/new?planId=1&dayId=1');
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Giorno A'), findsOneWidget);
    expect(find.text('Panca piana'), findsOneWidget);
  });

  testWidgets('la card sparisce quando la sessione viene chiusa', (
    tester,
  ) async {
    final plans = FakePlanRepository();
    final logs = FakeWorkoutLogRepository();
    final plan = seedPlan(plans);
    final log = logs.startSession(plan: plan, day: plan.days.first);

    await pumpApp(tester, plans: plans, logs: logs);
    await tester.tap(find.text('Più tardi'));
    await tester.pumpAndSettle();
    expect(find.text('Allenamento in corso'), findsOneWidget);

    log
      ..status = WorkoutStatus.completed
      ..finishedAt = DateTime(2026, 8, 15, 19);
    logs.saveLog(log);
    await tester.pumpAndSettle();

    expect(find.text('Allenamento in corso'), findsNothing);
  });
}
