import 'package:tacca/data/entities/block.dart';
import 'package:tacca/data/entities/exercise.dart';
import 'package:tacca/data/entities/workout_day.dart';
import 'package:tacca/data/entities/workout_plan.dart';
import 'package:tacca/data/repositories/workout_log_repository.dart';
import 'package:tacca/features/workout/bloc/workout_session_bloc.dart';
import 'package:tacca/features/workout/bloc/workout_session_event.dart';
import 'package:tacca/features/workout/pages/workout_session_page.dart';
import 'package:tacca/l10n/app_localizations.dart';
import 'package:tacca/services/timer/timer_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart' hide Block;
import 'package:intl/date_symbol_data_local.dart';

import '../../../support/fakes.dart';

final _now = DateTime(2026, 8, 15, 18);

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  late FakePlanRepository plans;
  late FakeWorkoutLogRepository logs;
  late TimerEngine timerEngine;

  WorkoutPlan buildPlan() {
    final plan = WorkoutPlan(
      name: 'Upper / Lower',
      createdAt: _now,
      updatedAt: _now,
    )..id = 1;
    final day = WorkoutDay(label: 'Giorno A')..id = 10;
    final block = Block.ofType(BlockType.standard)..id = 100;
    block.exercises.addAll([
      Exercise(name: 'Panca piana', sets: 2, reps: '8', restSeconds: 120)
        ..id = 1000,
      Exercise(name: 'Rematore', sets: 2, reps: '10')..id = 1001,
    ]);
    day.blocks.add(block);
    plan.days.add(day);

    final supersetDay = WorkoutDay(label: 'Giorno B', sortOrder: 1)..id = 11;
    final superset = Block.ofType(BlockType.superset)
      ..id = 101
      ..rounds = 4
      ..restBetweenRoundsSeconds = 60;
    superset.exercises.addAll([
      Exercise(name: 'Curl EZ', reps: '10')..id = 1002,
      Exercise(name: 'French press', reps: '10', sortOrder: 1)..id = 1003,
    ]);
    supersetDay.blocks.add(superset);
    plan.days.add(supersetDay);
    return plan;
  }

  setUp(() {
    plans = FakePlanRepository()..add(buildPlan());
    logs = FakeWorkoutLogRepository();
    // Orologio fermo e tick lentissimo: il timer non produce frame durante il
    // test, così `pumpAndSettle` termina.
    timerEngine = TimerEngine(
      now: () => _now,
      tickInterval: const Duration(minutes: 30),
    );
  });

  tearDown(() async {
    await timerEngine.dispose();
    await logs.dispose();
  });

  Future<void> pumpSession(WidgetTester tester, {int dayId = 10}) async {
    // Le card della sessione sono alte quanto quelle del design: sulla
    // finestra di default (800×600) la lista non costruirebbe il secondo
    // esercizio di un superset e le asserzioni non lo troverebbero.
    tester.view.physicalSize = const Size(1200, 4800);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // I test verificano le stringhe italiane: senza fissare la lingua
        // la locale di test (en_US) non è fra quelle tradotte e Flutter
        // ripiegherebbe sulla prima in ordine alfabetico, il tedesco.
        locale: const Locale('it'),
        routerConfig: GoRouter(
          initialLocation: '/',
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => BlocProvider(
                create: (context) => WorkoutSessionBloc(
                  planRepository: plans,
                  logRepository: logs,
                  timerEngine: timerEngine,
                  feedback: RecordingSessionFeedback(),
                  notifier: RecordingSessionNotifier(),
                  screenWake: RecordingScreenWake(),
                  liveSession: RecordingLiveSession(),
                  liveLabels: kTestLiveLabels,
                  now: () => _now,
                )..add(SessionStarted(planId: 1, dayId: dayId)),
                child: const WorkoutSessionPage(),
              ),
            ),
            GoRoute(
              path: '/history/:logId',
              builder: (context, state) => Scaffold(
                body: Text('DETTAGLIO ${state.pathParameters['logId']}'),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('mostra gli esercizi del giorno con la prescrizione', (
    tester,
  ) async {
    await pumpSession(tester);

    expect(find.text('Giorno A'), findsOneWidget);
    expect(find.text('Panca piana'), findsOneWidget);
    expect(find.text('2×8 · rec 120s'), findsOneWidget);
    expect(find.text('Rematore'), findsOneWidget);
    expect(find.text('Serie 1'), findsNWidgets(2));
  });

  testWidgets('il superset mostra giri, recupero del giro e coppia A/B', (
    tester,
  ) async {
    await pumpSession(tester, dayId: 11);

    expect(find.text('Superset'), findsOneWidget);
    expect(find.text('4 giri'), findsOneWidget);
    expect(find.text('60s tra i giri'), findsOneWidget);
    // Gli esercizi si leggono come una coppia, non come due voci in fila.
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    // Le righe da spuntare sono i giri del gruppo, non serie del singolo.
    expect(find.text('Giro 1'), findsNWidgets(2));
    expect(find.text('Giro 4'), findsNWidgets(2));
    expect(find.textContaining('Serie'), findsNothing);
    expect(find.text('0/4 giri'), findsNWidgets(2));
  });

  testWidgets('nel superset il recupero parte alla fine del giro', (
    tester,
  ) async {
    await pumpSession(tester, dayId: 11);

    // Primo esercizio: si incatena subito al secondo, nessun countdown.
    await tester.tap(find.byKey(const ValueKey('set-toggle-Giro 1')).first);
    await tester.pumpAndSettle();
    expect(find.text('Ferma'), findsNothing);

    // Secondo (ultimo) esercizio: il giro è chiuso, parte il minuto di recupero.
    final secondExercise = find
        .descendant(
          of: find.byKey(const ValueKey('session-item-1')),
          matching: find.byKey(const ValueKey('set-toggle-Giro 1')),
        )
        .first;
    await tester.ensureVisible(secondExercise);
    await tester.pumpAndSettle();
    await tester.tap(secondExercise);
    await tester.pumpAndSettle();
    expect(find.text('01:00'), findsOneWidget);
  });

  testWidgets('spuntare una serie la registra e avvia il recupero', (
    tester,
  ) async {
    await pumpSession(tester);

    await tester.tap(find.byKey(const ValueKey('set-toggle-Serie 1')).first);
    await tester.pumpAndSettle();

    // La spunta è registrata: lo dice il contatore della card.
    expect(find.text('1/2 serie'), findsOneWidget);
    // La barra del timer di recupero compare con il countdown a 2 minuti.
    expect(find.text('02:00'), findsOneWidget);
    expect(find.text('Ferma'), findsOneWidget);
  });

  testWidgets('il log rapido si apre precompilato con l\'ultima volta', (
    tester,
  ) async {
    logs.lastPerformances['Panca piana'] = LastPerformance(
      performedAt: DateTime(2026, 8, 8),
      sets: [buildLogSet(1, weightKg: 75, reps: '8')],
    );
    await pumpSession(tester);

    expect(find.textContaining('Ultima volta'), findsOneWidget);

    await tester.tap(find.text('Serie 1').first);
    await tester.pumpAndSettle();

    expect(find.text('Panca piana — serie 1'), findsOneWidget);
    final weight = tester.widget<TextField>(
      find.byKey(const ValueKey('set-weight')),
    );
    expect(weight.controller!.text, '75');

    // +2,5 kg e salva: il valore finisce nella card.
    await tester.tap(find.byTooltip('+2,5'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();

    expect(find.text('77.5 kg × 8'), findsOneWidget);
  });

  testWidgets('terminare la sessione mostra il riepilogo e apre lo storico', (
    tester,
  ) async {
    await pumpSession(tester);

    await tester.tap(find.byKey(const ValueKey('set-toggle-Serie 1')).first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Termina'));
    await tester.pumpAndSettle();

    expect(find.text('Riepilogo sessione'), findsOneWidget);
    expect(find.text('Serie registrate'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('session-notes')),
      'Buona sessione',
    );
    await tester.tap(find.text('Termina sessione'));
    await tester.pumpAndSettle();

    expect(find.textContaining('DETTAGLIO'), findsOneWidget);
    final log = logs.logs.values.single;
    expect(log.notes, 'Buona sessione');
  });

  testWidgets(
    'in background la pagina programma la notifica con le stringhe tradotte',
    (tester) async {
      late RecordingSessionNotifier notifier;
      tester.view.physicalSize = const Size(1200, 4800);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp.router(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          // I test verificano le stringhe italiane: senza fissare la lingua
          // la locale di test (en_US) non è fra quelle tradotte e Flutter
          // ripiegherebbe sulla prima in ordine alfabetico, il tedesco.
          locale: const Locale('it'),
          routerConfig: GoRouter(
            initialLocation: '/',
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => BlocProvider(
                  create: (context) => WorkoutSessionBloc(
                    planRepository: plans,
                    logRepository: logs,
                    timerEngine: timerEngine,
                    feedback: RecordingSessionFeedback(),
                    notifier: notifier = RecordingSessionNotifier(),
                    screenWake: RecordingScreenWake(),
                    liveSession: RecordingLiveSession(),
                    liveLabels: kTestLiveLabels,
                    now: () => _now,
                  )..add(SessionStarted(planId: 1, dayId: 10)),
                  child: const WorkoutSessionPage(),
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Un recupero in corso: è ciò che, andando in background, va tradotto in
      // notifica locale al posto del beep.
      await tester.tap(find.byKey(const ValueKey('set-toggle-Serie 1')).first);
      await tester.pumpAndSettle();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();

      // Nessuna eccezione (il callback di lifecycle non fa lookup che ascoltano
      // un InheritedWidget) e le stringhe arrivano tradotte dagli ARB.
      expect(tester.takeException(), isNull);
      expect(notifier.scheduledText, isNotEmpty);
      expect(notifier.scheduledText.last.title, 'Timer allenamento');
      expect(
        notifier.scheduledText.last.body,
        'È scattato un segnale del timer.',
      );
    },
  );

  testWidgets('uscire dalla sessione chiede conferma e la lascia aperta', (
    tester,
  ) async {
    await pumpSession(tester);

    // Il back di sistema passa dal PopScope della pagina.
    final dynamic widgetsBinding = WidgetsBinding.instance;
    await widgetsBinding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Uscire dalla sessione?'), findsOneWidget);

    await tester.tap(find.text('Continua'));
    await tester.pumpAndSettle();

    expect(find.text('Panca piana'), findsOneWidget);
  });
}
