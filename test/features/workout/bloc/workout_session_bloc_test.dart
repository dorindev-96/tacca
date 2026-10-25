import 'package:tacca/data/entities/block.dart';
import 'package:tacca/data/entities/exercise.dart';
import 'package:tacca/data/entities/log_entry.dart';
import 'package:tacca/data/entities/workout_day.dart';
import 'package:tacca/data/entities/workout_log.dart';
import 'package:tacca/data/entities/workout_plan.dart';
import 'package:tacca/data/repositories/workout_log_repository.dart';
import 'package:tacca/features/workout/bloc/workout_session_bloc.dart';
import 'package:tacca/features/workout/bloc/workout_session_event.dart';
import 'package:tacca/features/workout/bloc/workout_session_state.dart';
import 'package:tacca/services/live_session/live_session_controller.dart';
import 'package:tacca/services/timer/timer_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fakes.dart';

final _now = DateTime(2026, 8, 15, 18);

void main() {
  late FakePlanRepository plans;
  late FakeWorkoutLogRepository logs;
  late RecordingSessionFeedback feedback;
  late RecordingSessionNotifier notifier;
  late RecordingScreenWake screenWake;
  late RecordingLiveSession live;
  late TimerEngine timerEngine;

  /// Scheda a un giorno: due esercizi in un blocco standard, il primo con
  /// recupero configurato (serve all'avvio automatico del countdown).
  WorkoutPlan buildPlan() {
    final plan = WorkoutPlan(
      name: 'Upper / Lower',
      createdAt: _now,
      updatedAt: _now,
    )..id = 1;
    final day = WorkoutDay(label: 'Giorno A')..id = 10;
    final block = Block.ofType(BlockType.standard)..id = 100;
    block.exercises.addAll([
      Exercise(name: 'Panca piana', sets: 3, reps: '8', restSeconds: 120)
        ..id = 1000,
      Exercise(name: 'Rematore', sets: 3, reps: '10')..id = 1001,
    ]);
    day.blocks.add(block);
    plan.days.add(day);

    // Giorno a superset: i giri e il recupero stanno sul blocco, gli esercizi
    // portano solo le ripetizioni — è la forma con cui arriva dalla scheda.
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

    // Giorno che apre con un riscaldamento a tempo: nessuna serie prescritta,
    // solo una durata. È la forma con cui arriva una scheda vera, e la riga
    // che la card disegna comunque.
    final warmupDay = WorkoutDay(label: 'Giorno C', sortOrder: 2)..id = 12;
    final warmupBlock = Block.ofType(BlockType.standard)..id = 102;
    warmupBlock.exercises.addAll([
      Exercise(name: 'Camminata in salita', durationSeconds: 300)..id = 1004,
      Exercise(
        name: 'Back squat',
        sets: 3,
        reps: '8-10',
        restSeconds: 120,
        sortOrder: 1,
      )..id = 1005,
    ]);
    warmupDay.blocks.add(warmupBlock);
    plan.days.add(warmupDay);

    // Un superset in mezzo a due esercizi normali: è dove il banner deve
    // passare da "serie" a "giro" e tornare indietro.
    final mixedDay = WorkoutDay(label: 'Giorno D', sortOrder: 3)..id = 13;
    final before = Block.ofType(BlockType.standard)..id = 103;
    before.exercises.add(
      Exercise(name: 'Squat', sets: 2, reps: '5', restSeconds: 90)..id = 1006,
    );
    final pair = Block.ofType(BlockType.superset, sortOrder: 1)
      ..id = 104
      ..rounds = 3
      ..restBetweenRoundsSeconds = 75;
    pair.exercises.addAll([
      Exercise(name: 'Trazioni', reps: '8')..id = 1007,
      Exercise(name: 'Dip', reps: '10', sortOrder: 1)..id = 1008,
    ]);
    final after = Block.ofType(BlockType.standard, sortOrder: 2)..id = 105;
    after.exercises.add(
      Exercise(name: 'Plank', durationSeconds: 60)..id = 1009,
    );
    mixedDay.blocks.addAll([before, pair, after]);
    plan.days.add(mixedDay);

    // Superset in cui il primo esercizio prescrive una serie in più: l'ultimo
    // giro lo fa da solo.
    final unevenDay = WorkoutDay(label: 'Giorno E', sortOrder: 4)..id = 14;
    final uneven = Block.ofType(BlockType.superset)
      ..id = 106
      ..rounds = 3
      ..restBetweenRoundsSeconds = 60;
    uneven.exercises.addAll([
      Exercise(name: 'Panca inclinata', sets: 4, reps: '10')..id = 1010,
      Exercise(name: 'Croci', reps: '12', sortOrder: 1)..id = 1011,
    ]);
    unevenDay.blocks.add(uneven);
    plan.days.add(unevenDay);

    // Circuito di tre, col recupero scritto sull'ultimo esercizio invece che
    // sul blocco: è un'altra forma con cui arriva una scheda vera.
    final circuitDay = WorkoutDay(label: 'Giorno F', sortOrder: 5)..id = 15;
    final circuit = Block.ofType(BlockType.circuit)
      ..id = 107
      ..rounds = 2;
    circuit.exercises.addAll([
      Exercise(name: 'Burpee', reps: '10')..id = 1012,
      Exercise(name: 'Kettlebell swing', reps: '15', sortOrder: 1)..id = 1013,
      Exercise(name: 'Box jump', reps: '8', restSeconds: 120, sortOrder: 2)
        ..id = 1014,
    ]);
    circuitDay.blocks.add(circuit);
    plan.days.add(circuitDay);
    return plan;
  }

  WorkoutSessionBloc buildBloc() => WorkoutSessionBloc(
    planRepository: plans,
    logRepository: logs,
    timerEngine: timerEngine,
    feedback: feedback,
    notifier: notifier,
    screenWake: screenWake,
    liveSession: live,
    liveLabels: kTestLiveLabels,
    now: () => _now,
  );

  Future<WorkoutSessionBloc> startedSession({int dayId = 10}) async {
    final bloc = buildBloc()..add(SessionStarted(planId: 1, dayId: dayId));
    await pumpEventQueue();
    return bloc;
  }

  setUp(() {
    plans = FakePlanRepository()..add(buildPlan());
    logs = FakeWorkoutLogRepository();
    feedback = RecordingSessionFeedback();
    notifier = RecordingSessionNotifier();
    screenWake = RecordingScreenWake();
    live = RecordingLiveSession();
    timerEngine = TimerEngine(now: () => _now);
  });

  tearDown(() async {
    await timerEngine.dispose();
    await logs.dispose();
    await live.dispose();
  });

  /// Giro confermato dalla schermata di blocco: `entryIndex` è il primo
  /// esercizio del gruppo, `setNumber` il giro.
  LiveSessionAction roundConfirmed(
    WorkoutSessionBloc bloc, {
    required DateTime at,
    String id = 'giro-1',
    int entryIndex = 0,
    int round = 1,
  }) => LiveSessionAction(
    id: id,
    kind: LiveSessionActionKind.roundCompleted,
    logId: bloc.state.log!.id,
    entryIndex: entryIndex,
    setNumber: round,
    at: at,
  );

  /// Conferma come la manda il nativo: id già assegnato e orario del tap.
  LiveSessionAction setConfirmed(
    WorkoutSessionBloc bloc, {
    required DateTime at,
    String id = 'azione-1',
    int entryIndex = 0,
    int setNumber = 1,
    int? logId,
  }) => LiveSessionAction(
    id: id,
    kind: LiveSessionActionKind.setCompleted,
    logId: logId ?? bloc.state.log!.id,
    entryIndex: entryIndex,
    setNumber: setNumber,
    at: at,
  );

  group('apertura della sessione', () {
    test('SessionStarted crea il log e tiene lo schermo acceso', () async {
      final bloc = await startedSession();

      expect(bloc.state.status, WorkoutSessionStatus.ready);
      expect(bloc.state.log, isNotNull);
      expect(bloc.state.day?.label, 'Giorno A');
      expect(bloc.state.items.map((i) => i.name), ['Panca piana', 'Rematore']);
      expect(screenWake.enabled, isTrue);
      expect(feedback.prepareCount, 1);

      await bloc.close();
    });

    test(
      'SessionStarted su scheda o giorno inesistenti finisce in notFound',
      () async {
        final bloc = buildBloc()
          ..add(const SessionStarted(planId: 1, dayId: 999));
        await pumpEventQueue();

        expect(bloc.state.status, WorkoutSessionStatus.notFound);

        await bloc.close();
      },
    );

    test('SessionResumed riallinea le entry alla scheda modificata', () async {
      // Sessione registrata su una scheda con "Panca piana" e "Curl", con una
      // serie svolta sul curl che è poi stato tolto dalla scheda.
      final plan = plans.plans[1]!;
      final day = plan.days.first;
      final log = WorkoutLog.start(
        startedAt: _now,
        planNameSnapshot: plan.name,
        dayLabelSnapshot: day.label,
      );
      log.plan.target = plan;
      log.day.target = day;
      final removed = LogEntry(exerciseNameSnapshot: 'Curl', sortOrder: 1);
      removed.sets.add(buildLogSet(1, weightKg: 12, reps: '12'));
      log.entries.addAll([
        LogEntry(exerciseNameSnapshot: 'Panca piana', sortOrder: 0),
        removed,
      ]);
      final logId = logs.saveLog(log);

      final bloc = buildBloc()..add(SessionResumed(logId));
      await pumpEventQueue();

      final names = bloc.state.items.map((i) => i.name).toList();
      expect(
        names,
        ['Panca piana', 'Rematore', 'Curl'],
        reason:
            'gli esercizi in scheda vengono riallineati, quelli svolti ma non '
            'più prescritti restano in coda',
      );
      expect(bloc.state.items[1].exercise?.name, 'Rematore');
      expect(
        bloc.state.items[2].block,
        isNull,
        reason: 'l\'esercizio orfano non ha più una prescrizione',
      );

      await bloc.close();
    });

    test('SessionResumed su un log inesistente finisce in notFound', () async {
      final bloc = buildBloc()..add(const SessionResumed(404));
      await pumpEventQueue();

      expect(bloc.state.status, WorkoutSessionStatus.notFound);

      await bloc.close();
    });
  });

  group('registrazione delle serie', () {
    test('SetCompleted registra la serie e salva subito (autosave)', () async {
      final bloc = await startedSession();
      final savesBefore = logs.saveCount;

      bloc.add(const SetCompleted(entryIndex: 0, setNumber: 1));
      await pumpEventQueue();

      final item = bloc.state.items.first;
      expect(item.isSetDone(1), isTrue);
      expect(
        logs.saveCount,
        savesBefore + 1,
        reason: 'ogni mutazione persiste subito (RF-06)',
      );

      await bloc.close();
    });

    test(
      'la serie eredita i valori della precedente della stessa sessione',
      () async {
        final bloc = await startedSession();

        bloc.add(const SetCompleted(entryIndex: 0, setNumber: 1));
        await pumpEventQueue();
        bloc.add(
          const SetLogged(entryIndex: 0, setNumber: 1, weightKg: 80, reps: '8'),
        );
        await pumpEventQueue();
        bloc.add(const SetCompleted(entryIndex: 0, setNumber: 2));
        await pumpEventQueue();

        final second = bloc.state.items.first.setNumbered(2)!;
        expect(second.weightKg, 80);
        expect(second.reps, '8');

        await bloc.close();
      },
    );

    test(
      'senza serie precedenti eredita i valori dell\'ultima volta',
      () async {
        logs.lastPerformances['Panca piana'] = LastPerformance(
          performedAt: DateTime(2026, 8, 8),
          sets: [buildLogSet(1, weightKg: 75, reps: '8')],
        );
        final bloc = await startedSession();

        bloc.add(const SetCompleted(entryIndex: 0, setNumber: 1));
        await pumpEventQueue();

        final first = bloc.state.items.first.setNumbered(1)!;
        expect(first.weightKg, 75);
        expect(first.reps, '8');

        await bloc.close();
      },
    );

    test('SetUnchecked rimuove la serie e salva', () async {
      final bloc = await startedSession();
      bloc.add(const SetCompleted(entryIndex: 0, setNumber: 1));
      await pumpEventQueue();
      final savesBefore = logs.saveCount;

      bloc.add(const SetUnchecked(entryIndex: 0, setNumber: 1));
      await pumpEventQueue();

      expect(bloc.state.items.first.isSetDone(1), isFalse);
      expect(logs.saveCount, savesBefore + 1);

      await bloc.close();
    });

    test('SetLogged crea la serie se non era ancora spuntata', () async {
      final bloc = await startedSession();

      bloc.add(
        const SetLogged(entryIndex: 1, setNumber: 1, weightKg: 40, reps: '10'),
      );
      await pumpEventQueue();

      final item = bloc.state.items[1];
      expect(item.isSetDone(1), isTrue);
      expect(item.setNumbered(1)!.weightKg, 40);

      await bloc.close();
    });
  });

  group('superset', () {
    test('i giri del blocco valgono come serie di ogni esercizio', () async {
      final bloc = await startedSession(dayId: 11);

      final items = bloc.state.items;
      expect(items.map((i) => i.name), ['Curl EZ', 'French press']);
      expect(items.every((i) => i.isRoundBased), isTrue);
      expect(items.map((i) => i.displayedSets), [4, 4]);
      expect(items.map((i) => i.isLastOfBlock), [false, true]);

      await bloc.close();
    });

    test('il recupero parte a fine giro, non fra i due esercizi', () async {
      final bloc = await startedSession(dayId: 11);

      // Primo esercizio del giro: si passa subito al secondo, niente timer.
      bloc.add(const SetCompleted(entryIndex: 0, setNumber: 1));
      await pumpEventQueue();
      expect(bloc.state.timer, isNull);

      // Ultimo esercizio: il giro è chiuso, parte il recupero del blocco.
      bloc.add(const SetCompleted(entryIndex: 1, setNumber: 1));
      await pumpEventQueue();
      expect(bloc.state.timer!.spec.kind, TimerKind.rest);
      expect(bloc.state.timer!.spec.total, const Duration(seconds: 60));

      await bloc.close();
    });
  });

  group('giro intero (superset e circuito)', () {
    test(
      'RoundCompleted spunta il giro di ogni esercizio e salva subito',
      () async {
        final bloc = await startedSession(dayId: 11);
        final savesBefore = logs.saveCount;

        bloc.add(const RoundCompleted(entryIndex: 0, round: 1));
        await pumpEventQueue();

        final items = bloc.state.items;
        expect(items.map((i) => i.isSetDone(1)), [true, true]);
        expect(items.map((i) => i.setNumbered(1)!.completedAt), [_now, _now]);
        expect(
          logs.saveCount,
          savesBefore + 1,
          reason: 'un giro è una mutazione sola, e si persiste subito',
        );

        await bloc.close();
      },
    );

    test('a giro chiuso parte il recupero del giro', () async {
      final bloc = await startedSession(dayId: 11);

      bloc.add(const RoundCompleted(entryIndex: 0, round: 1));
      await pumpEventQueue();

      expect(timerEngine.current!.spec.kind, TimerKind.rest);
      expect(timerEngine.current!.spec.total, const Duration(seconds: 60));
      expect(timerEngine.current!.startedAt, _now);
      // La barra del timer dice di quale giro è il recupero.
      expect(timerEngine.current!.spec.label, 'Curl EZ + French press');

      await bloc.close();
    });

    test(
      'ogni esercizio parte dai suoi valori, non da quelli dell\'altro',
      () async {
        logs.lastPerformances['Curl EZ'] = LastPerformance(
          performedAt: DateTime(2026, 8, 8),
          sets: [buildLogSet(1, weightKg: 30, reps: '10')],
        );
        logs.lastPerformances['French press'] = LastPerformance(
          performedAt: DateTime(2026, 8, 8),
          sets: [buildLogSet(1, weightKg: 20, reps: '12')],
        );
        final bloc = await startedSession(dayId: 11);

        bloc.add(const RoundCompleted(entryIndex: 0, round: 1));
        await pumpEventQueue();

        final items = bloc.state.items;
        expect(items[0].setNumbered(1)!.weightKg, 30);
        expect(items[1].setNumbered(1)!.weightKg, 20);
        expect(items[1].setNumbered(1)!.reps, '12');

        await bloc.close();
      },
    );

    test('un giro cominciato a mano si chiude spuntando il resto', () async {
      final bloc = await startedSession(dayId: 11);
      bloc.add(
        const SetLogged(entryIndex: 0, setNumber: 1, weightKg: 32, reps: '8'),
      );
      await pumpEventQueue();

      // Qualunque esercizio del gruppo identifica il giro.
      bloc.add(const RoundCompleted(entryIndex: 1, round: 1));
      await pumpEventQueue();

      final items = bloc.state.items;
      expect(items[0].entry.sets, hasLength(1));
      expect(
        items[0].setNumbered(1)!.weightKg,
        32,
        reason: 'la serie già registrata non si tocca',
      );
      expect(items[1].isSetDone(1), isTrue);
      expect(timerEngine.current!.spec.total, const Duration(seconds: 60));

      await bloc.close();
    });

    test('lo stesso giro confermato due volte vale una', () async {
      final bloc = await startedSession(dayId: 11);

      bloc.add(const RoundCompleted(entryIndex: 0, round: 1));
      await pumpEventQueue();
      final savesBefore = logs.saveCount;
      bloc.add(const RoundCompleted(entryIndex: 0, round: 1));
      await pumpEventQueue();

      expect(bloc.state.items.map((i) => i.entry.sets.length), [1, 1]);
      expect(logs.saveCount, savesBefore, reason: 'non c\'era niente da fare');

      await bloc.close();
    });

    test(
      'l\'evidenza passa al giro dopo, poi a ciò che segue il superset',
      () async {
        final bloc = await startedSession(dayId: 13);
        bloc.add(const ExerciseFocused(2));
        await pumpEventQueue();

        bloc.add(const RoundCompleted(entryIndex: 1, round: 1));
        await pumpEventQueue();
        // Il giro 2 riparte dal primo esercizio della coppia.
        expect(bloc.state.currentIndex, 1);
        expect(bloc.state.currentRound!.number, 2);

        bloc.add(const RoundCompleted(entryIndex: 1, round: 2));
        bloc.add(const RoundCompleted(entryIndex: 1, round: 3));
        await pumpEventQueue();
        // Superset finito: si va avanti, non si torna indietro allo squat
        // saltato — quello arriva dopo, a fine giornata.
        expect(bloc.state.items[bloc.state.currentIndex].name, 'Plank');
        expect(bloc.state.currentRound, isNull);

        await bloc.close();
      },
    );

    test(
      'chi prescrive più serie degli altri fa l\'ultimo giro da solo',
      () async {
        final bloc = await startedSession(dayId: 14);
        for (var round = 1; round <= 3; round++) {
          bloc.add(RoundCompleted(entryIndex: 0, round: round));
        }
        await pumpEventQueue();
        bloc.add(const TimerStopped());
        await pumpEventQueue();

        final round4 = bloc.state.currentRound!;
        expect(round4.number, 4);
        expect(round4.title, 'Panca inclinata');

        bloc.add(const RoundCompleted(entryIndex: 0, round: 4));
        await pumpEventQueue();

        final items = bloc.state.items;
        expect(items[0].entry.sets, hasLength(4));
        expect(
          items[1].entry.sets,
          hasLength(3),
          reason: 'nessun giro inventato',
        );
        // Il giro è chiuso anche se a chiuderlo non è l'ultimo del blocco.
        expect(timerEngine.current!.spec.total, const Duration(seconds: 60));
        expect(bloc.state.currentRound, isNull);

        await bloc.close();
      },
    );

    test('nel circuito il giro spunta tutti gli esercizi', () async {
      final bloc = await startedSession(dayId: 15);

      expect(
        bloc.state.currentRound!.title,
        'Burpee + Kettlebell swing + Box jump',
      );

      bloc.add(const RoundCompleted(entryIndex: 0, round: 1));
      await pumpEventQueue();

      expect(bloc.state.items.every((i) => i.isSetDone(1)), isTrue);
      // Senza recupero sul blocco vale quello di chi chiude il giro.
      expect(timerEngine.current!.spec.total, const Duration(minutes: 2));
      expect(bloc.state.currentRound!.number, 2);

      await bloc.close();
    });

    test('col recupero automatico spento il giro si spunta e basta', () async {
      final bloc = await startedSession(dayId: 11);
      bloc.add(const AutoStartRestToggled(false));

      bloc.add(const RoundCompleted(entryIndex: 0, round: 1));
      await pumpEventQueue();

      expect(bloc.state.items.every((i) => i.isSetDone(1)), isTrue);
      expect(timerEngine.current, isNull);

      await bloc.close();
    });

    test('un timer già in corso non viene interrotto dal giro', () async {
      final bloc = await startedSession(dayId: 11);
      bloc.add(TimerRequested(TimerSpec.amrap(const Duration(minutes: 10))));
      await pumpEventQueue();

      bloc.add(const RoundCompleted(entryIndex: 0, round: 1));
      await pumpEventQueue();

      expect(bloc.state.items.every((i) => i.isSetDone(1)), isTrue);
      expect(timerEngine.current!.spec.kind, TimerKind.amrap);
      expect(bloc.state.pendingTimerRequest, isNull);

      await bloc.close();
    });

    test('fuori da un superset il giro vale come la serie', () async {
      // Un'azione rimasta in coda mentre la scheda cambiava: il gruppo si
      // ricalcola adesso, e se non c'è più resta la serie di quell'esercizio.
      final bloc = await startedSession();

      bloc.add(const RoundCompleted(entryIndex: 0, round: 1));
      await pumpEventQueue();

      expect(bloc.state.items.map((i) => i.isSetDone(1)), [true, false]);
      expect(timerEngine.current!.spec.total, const Duration(minutes: 2));

      await bloc.close();
    });

    test('il pulsante del giro esiste solo dentro un gruppo', () async {
      final bloc = await startedSession(dayId: 13);

      // Squat: esercizio normale.
      expect(bloc.state.currentRound, isNull);

      // Dip, il secondo della coppia: il giro è comunque quello del gruppo.
      bloc.add(const ExerciseFocused(2));
      await pumpEventQueue();
      final round = bloc.state.currentRound!;
      expect(round.number, 1);
      expect(round.anchor.name, 'Trazioni');
      expect(round.title, 'Trazioni + Dip');
      expect(round.total, 3);

      await bloc.close();
    });
  });

  group('timer', () {
    test('la spunta avvia da sola il recupero dell\'esercizio', () async {
      final bloc = await startedSession();

      bloc.add(const SetCompleted(entryIndex: 0, setNumber: 1));
      await pumpEventQueue();

      expect(bloc.state.timer, isNotNull);
      expect(bloc.state.timer!.spec.kind, TimerKind.rest);
      expect(bloc.state.timer!.spec.total, const Duration(seconds: 120));

      await bloc.close();
    });

    test('nessun avvio automatico se l\'esercizio non ha recupero', () async {
      final bloc = await startedSession();

      bloc.add(const SetCompleted(entryIndex: 1, setNumber: 1));
      await pumpEventQueue();

      expect(bloc.state.timer, isNull);

      await bloc.close();
    });

    test(
      'con l\'avvio automatico disattivato la spunta non parte il timer',
      () async {
        final bloc = await startedSession();
        bloc.add(const AutoStartRestToggled(false));
        await pumpEventQueue();

        bloc.add(const SetCompleted(entryIndex: 0, setNumber: 1));
        await pumpEventQueue();

        expect(bloc.state.timer, isNull);

        await bloc.close();
      },
    );

    test(
      'un timer già attivo non viene interrotto dall\'avvio automatico',
      () async {
        final bloc = await startedSession();
        bloc.add(TimerRequested(TimerSpec.amrap(const Duration(minutes: 15))));
        await pumpEventQueue();

        bloc.add(const SetCompleted(entryIndex: 0, setNumber: 1));
        await pumpEventQueue();

        expect(bloc.state.timer!.spec.kind, TimerKind.amrap);
        expect(bloc.state.pendingTimerRequest, isNull);

        await bloc.close();
      },
    );

    test('avviare a mano un timer con uno attivo chiede conferma', () async {
      final bloc = await startedSession();
      bloc.add(TimerRequested(TimerSpec.amrap(const Duration(minutes: 15))));
      await pumpEventQueue();

      bloc.add(TimerRequested(TimerSpec.rest(const Duration(seconds: 90))));
      await pumpEventQueue();

      expect(bloc.state.pendingTimerRequest, isNotNull);
      expect(
        bloc.state.timer!.spec.kind,
        TimerKind.amrap,
        reason: 'finché non c\'è conferma il timer in corso resta',
      );

      bloc.add(
        TimerRequested(
          TimerSpec.rest(const Duration(seconds: 90)),
          force: true,
        ),
      );
      await pumpEventQueue();

      expect(bloc.state.pendingTimerRequest, isNull);
      expect(bloc.state.timer!.spec.kind, TimerKind.rest);

      await bloc.close();
    });

    test('TimerStopped ferma il timer e libera la barra', () async {
      final bloc = await startedSession();
      bloc.add(TimerRequested(TimerSpec.rest(const Duration(minutes: 2))));
      await pumpEventQueue();

      bloc.add(const TimerStopped());
      await pumpEventQueue();

      expect(bloc.state.timer, isNull);
      expect(timerEngine.isRunning, isFalse);

      await bloc.close();
    });

    test('i segnali del timer diventano beep e vibrazione', () async {
      final bloc = await startedSession();

      bloc.add(const TimerSignalled(TimerSignal.interval));
      await pumpEventQueue();

      expect(feedback.signals, [TimerSignal.interval]);

      await bloc.close();
    });
  });

  group('lifecycle', () {
    test('in background programma le notifiche dei segnali futuri', () async {
      final bloc = await startedSession();
      bloc.add(
        TimerRequested(
          TimerSpec.emom(
            interval: const Duration(seconds: 60),
            total: const Duration(minutes: 5),
          ),
        ),
      );
      await pumpEventQueue();

      bloc.add(
        const AppLifecycleChanged(
          toBackground: true,
          notificationTitle: 'Timer',
          notificationBody: 'Segnale',
        ),
      );
      await pumpEventQueue();

      expect(notifier.scheduled, hasLength(1));
      expect(
        notifier.scheduled.single,
        hasLength(5),
        reason: 'quattro inizi round più la fine',
      );

      await bloc.close();
    });

    test('al rientro annulla le notifiche pendenti', () async {
      final bloc = await startedSession();

      bloc.add(const AppLifecycleChanged(toBackground: false));
      await pumpEventQueue();

      expect(notifier.cancelCount, greaterThan(0));

      await bloc.close();
    });

    test('scendere in background programma una volta sola', () async {
      // iOS annuncia il passaggio due volte (`hidden` poi `paused`) e ripassa
      // da `hidden` risalendo: riprogrammare a ogni annuncio vuol dire
      // rifare undici `cancel` piu dieci `zonedSchedule` proprio mentre il
      // sistema sta sospendendo il processo (spike S-01).
      final bloc = await startedSession();
      bloc.add(TimerRequested(TimerSpec.rest(const Duration(seconds: 90))));
      await pumpEventQueue();

      bloc.add(const AppLifecycleChanged(toBackground: true));
      bloc.add(const AppLifecycleChanged(toBackground: true));
      await pumpEventQueue();

      expect(notifier.scheduled, hasLength(1));

      await bloc.close();
    });

    test('dopo un rientro il background successivo riprogramma', () async {
      // La diserzione vale per un solo passaggio: il secondo e un'altra cosa.
      final bloc = await startedSession();
      bloc.add(TimerRequested(TimerSpec.rest(const Duration(seconds: 90))));
      await pumpEventQueue();

      bloc.add(const AppLifecycleChanged(toBackground: true));
      await pumpEventQueue();
      bloc.add(const AppLifecycleChanged(toBackground: false));
      await pumpEventQueue();
      bloc.add(const AppLifecycleChanged(toBackground: true));
      await pumpEventQueue();

      expect(notifier.scheduled, hasLength(2));

      await bloc.close();
    });

    test(
      'il rientro ripulisce anche quando il Bloc non sa di essere stato via',
      () async {
        // A processo ucciso il Bloc nasce da zero, ma le notifiche programmate
        // prima — e il beep di fine recupero dell'isolate Android — sono
        // ancora armate: il rientro non si diserta mai.
        final bloc = await startedSession();
        final prima = notifier.cancelCount;

        bloc.add(const AppLifecycleChanged(toBackground: false));
        await pumpEventQueue();

        expect(notifier.cancelCount, greaterThan(prima));

        await bloc.close();
      },
    );
  });

  group('chiusura', () {
    test('SessionFinished chiude il log come completato e lo salva', () async {
      final bloc = await startedSession();
      bloc.add(const SetCompleted(entryIndex: 0, setNumber: 1));
      await pumpEventQueue();

      bloc.add(
        const SessionFinished(
          status: WorkoutStatus.completed,
          notes: '  Buona sessione  ',
        ),
      );
      await pumpEventQueue();

      final log = bloc.state.log!;
      expect(bloc.state.status, WorkoutSessionStatus.finished);
      expect(log.status, WorkoutStatus.completed);
      expect(log.finishedAt, _now);
      expect(log.notes, 'Buona sessione');
      expect(logs.logs[log.id]!.status, WorkoutStatus.completed);
      expect(screenWake.enabled, isFalse);

      await bloc.close();
    });

    test(
      'SessionFinished con esito interrotto resta comunque nello storico',
      () async {
        final bloc = await startedSession();

        bloc.add(const SessionFinished(status: WorkoutStatus.aborted));
        await pumpEventQueue();

        expect(bloc.state.log!.status, WorkoutStatus.aborted);
        expect(bloc.state.log!.notes, isNull);

        await bloc.close();
      },
    );

    test('chiudere il Bloc spegne timer, notifiche e wake lock', () async {
      final bloc = await startedSession();
      bloc.add(TimerRequested(TimerSpec.rest(const Duration(minutes: 2))));
      await pumpEventQueue();

      await bloc.close();

      expect(timerEngine.isRunning, isFalse);
      expect(screenWake.enabled, isFalse);
    });
  });

  group('schermata di blocco (RF-06)', () {
    test(
      'la sessione aperta finisce subito sulla superficie di sistema',
      () async {
        final bloc = await startedSession();

        final snapshot = live.started.single;
        expect(snapshot.exerciseName, 'Panca piana');
        expect(snapshot.setNumber, 1);
        expect(snapshot.totalSets, 3);
        expect(snapshot.canCompleteSet, isTrue);
        // Il countdown lo fa partire il nativo da solo: deve sapere quanto dura.
        expect(snapshot.restSecondsOnComplete, 120);
        expect(snapshot.labels, kTestLiveLabels);

        await bloc.close();
      },
    );

    test('insieme all\'esercizio corrente viaggia anche quello dopo', () async {
      // Senza, alla conferma dell'ultima serie il nativo conterebbe "4/3":
      // da solo non sa cosa viene dopo.
      final bloc = await startedSession();

      final snapshot = live.started.single;
      expect(snapshot.nextExerciseName, 'Rematore');
      expect(snapshot.nextEntryIndex, 1);
      expect(snapshot.nextSetNumber, 1);
      expect(snapshot.nextTotalSets, 3);
      expect(snapshot.nextRestSecondsOnComplete, 0);

      await bloc.close();
    });

    test(
      'un esercizio senza serie prescritte arriva comunque sulla superficie',
      () async {
        // Il riscaldamento a tempo non prescrive serie: contando solo quelle
        // prescritte spariva dal banner, che partiva già dall'esercizio dopo
        // mentre l'app evidenziava ancora questo.
        final bloc = await startedSession(dayId: 12);

        final snapshot = live.started.single;
        expect(snapshot.exerciseName, 'Camminata in salita');
        expect(snapshot.entryIndex, 0);
        expect(snapshot.setNumber, 1);
        // Zero, non uno: il nativo scrive "Serie 1" senza denominatore, come
        // la card non disegna nessuna chip del conteggio.
        expect(snapshot.totalSets, 0);
        expect(snapshot.canCompleteSet, isTrue);
        expect(snapshot.nextExerciseName, 'Back squat');
        expect(snapshot.nextSetNumber, 1);
        expect(snapshot.nextTotalSets, 3);

        await bloc.close();
      },
    );

    test(
      'confermata la sua unica serie, la superficie passa al successivo',
      () async {
        final bloc = await startedSession(dayId: 12);

        live.deliver(setConfirmed(bloc, at: _now));
        await pumpEventQueue();

        expect(bloc.state.items.first.entry.sets, hasLength(1));
        expect(live.last!.exerciseName, 'Back squat');
        expect(live.last!.setNumber, 1);
        expect(live.last!.totalSets, 3);

        await bloc.close();
      },
    );

    test('in un superset il banner mostra il giro intero', () async {
      // Durante il giro non ci si ferma a spuntare: il telefono si riprende in
      // mano alla fine, e un tocco solo deve chiudere entrambi gli esercizi.
      final bloc = await startedSession(dayId: 11);

      final snapshot = live.started.single;
      expect(snapshot.exerciseName, 'Curl EZ + French press');
      expect(snapshot.entryIndex, 0);
      expect(snapshot.setNumber, 1);
      expect(snapshot.totalSets, 4);
      expect(snapshot.completesRound, isTrue);
      // Il giro dopo è dello stesso gruppo: il nativo conta avanti i giri come
      // conterebbe le serie.
      expect(snapshot.advancesToNext, isFalse);
      // Il recupero del giro parte dal tap, senza aspettare l'app.
      expect(snapshot.restSecondsOnComplete, 60);
      expect(snapshot.nextExerciseName, isNull);

      await bloc.close();
    });

    test('confermato un giro, il banner passa al giro dopo', () async {
      final bloc = await startedSession(dayId: 11);

      bloc.add(const RoundCompleted(entryIndex: 0, round: 1));
      await pumpEventQueue();

      expect(live.last!.exerciseName, 'Curl EZ + French press');
      expect(live.last!.setNumber, 2);
      expect(live.last!.completesRound, isTrue);
      expect(live.last!.countdownEndsAt, _now.add(const Duration(seconds: 60)));

      await bloc.close();
    });

    test(
      'spuntato a mano il primo, il pulsante chiude il resto del giro',
      () async {
        final bloc = await startedSession(dayId: 11);

        bloc.add(const SetCompleted(entryIndex: 0, setNumber: 1));
        await pumpEventQueue();

        // Resta il giro 1, non "French press 1": il pulsante dice cosa si
        // chiude, e il recupero è ancora quello del giro.
        expect(live.last!.exerciseName, 'Curl EZ + French press');
        expect(live.last!.setNumber, 1);
        expect(live.last!.completesRound, isTrue);
        expect(live.last!.restSecondsOnComplete, 60);

        await bloc.close();
      },
    );

    test('il superset arriva sul banner come passo dopo, e se ne va', () async {
      final bloc = await startedSession(dayId: 13);

      final squat = live.started.single;
      expect(squat.exerciseName, 'Squat');
      expect(squat.completesRound, isFalse);
      expect(squat.nextExerciseName, 'Trazioni + Dip');
      expect(squat.nextEntryIndex, 1);
      expect(squat.nextSetNumber, 1);
      expect(squat.nextTotalSets, 3);
      expect(squat.nextRestSecondsOnComplete, 75);
      // Arrivato lì, il pulsante deve chiudere il giro, non la serie.
      expect(squat.nextCompletesRound, isTrue);
      // E da lì può contare avanti i giri da solo.
      expect(squat.nextAdvancesToNext, isFalse);

      bloc.add(const ExerciseFocused(2));
      await pumpEventQueue();

      final pair = live.last!;
      expect(pair.exerciseName, 'Trazioni + Dip');
      expect(pair.entryIndex, 1);
      expect(pair.completesRound, isTrue);
      expect(pair.nextExerciseName, 'Plank');
      expect(pair.nextCompletesRound, isFalse);

      await bloc.close();
    });

    test('il giro confermato dal blocco vale con l\'orario del tap', () async {
      final bloc = await startedSession(dayId: 11);
      final tap = _now.subtract(const Duration(seconds: 20));

      live.deliver(roundConfirmed(bloc, at: tap));
      await pumpEventQueue();

      final items = bloc.state.items;
      expect(items.map((i) => i.setNumbered(1)!.completedAt), [tap, tap]);
      // Il recupero del giro parte dal tap: ne restano 40 secondi su 60.
      expect(timerEngine.current!.startedAt, tap);
      expect(timerEngine.current!.remaining, const Duration(seconds: 40));

      await bloc.close();
    });

    test('il giro rimasto in coda si applica al rientro, una volta', () async {
      final bloc = await startedSession(dayId: 11);
      final tap = _now.subtract(const Duration(seconds: 10));
      live.pending = [roundConfirmed(bloc, at: tap)];
      // Lo stesso tap consegnato anche dallo stream, con l'app ancora viva.
      live.deliver(roundConfirmed(bloc, at: tap));
      await pumpEventQueue();

      bloc.add(const AppLifecycleChanged(toBackground: false));
      await pumpEventQueue();

      expect(bloc.state.items.map((i) => i.entry.sets.length), [1, 1]);

      await bloc.close();
    });

    test('fuori dai blocchi a giri si continua a contare avanti', () async {
      // La controprova: se `advancesToNext` fosse sempre vero, il nativo non
      // riuscirebbe più a spuntare due serie di fila senza riaprire l'app.
      final bloc = await startedSession();

      expect(live.started.single.exerciseName, 'Panca piana');
      expect(live.started.single.advancesToNext, isFalse);
      expect(live.started.single.nextAdvancesToNext, isFalse);

      await bloc.close();
    });

    test('sull\'ultimo esercizio rimasto non c\'è nessun "dopo"', () async {
      final bloc = await startedSession();

      for (var setNumber = 1; setNumber <= 3; setNumber++) {
        bloc.add(SetCompleted(entryIndex: 0, setNumber: setNumber));
      }
      await pumpEventQueue();

      expect(live.last!.exerciseName, 'Rematore');
      expect(live.last!.setNumber, 1);
      // Il nativo nasconderà il pulsante invece di inventare una serie.
      expect(live.last!.nextExerciseName, isNull);
      expect(live.last!.nextSetNumber, 0);

      await bloc.close();
    });

    test(
      'del prossimo esercizio si manda la serie vera, non "la prima"',
      () async {
        final bloc = await startedSession();

        // Rematore ha già la sua prima serie a registro (spuntata prima di
        // tornare indietro): il nativo deve puntare alla seconda.
        bloc.add(const SetCompleted(entryIndex: 1, setNumber: 1));
        bloc.add(const ExerciseFocused(0));
        await pumpEventQueue();

        expect(live.last!.exerciseName, 'Panca piana');
        expect(live.last!.nextExerciseName, 'Rematore');
        expect(live.last!.nextSetNumber, 2);

        await bloc.close();
      },
    );

    test('spuntata una serie, la superficie punta alla successiva', () async {
      final bloc = await startedSession();

      bloc.add(const SetCompleted(entryIndex: 0, setNumber: 1));
      await pumpEventQueue();

      expect(live.last!.setNumber, 2);
      expect(live.last!.countdownEndsAt, _now.add(const Duration(minutes: 2)));
      expect(live.last!.countdownLabel, 'Recupero');

      await bloc.close();
    });

    test(
      'la conferma dal blocco registra la serie con l\'orario del tap',
      () async {
        final bloc = await startedSession();
        final tap = _now.subtract(const Duration(seconds: 30));

        live.deliver(setConfirmed(bloc, at: tap));
        await pumpEventQueue();

        final sets = bloc.state.items.first.entry.sets;
        expect(sets, hasLength(1));
        expect(sets.first.completedAt, tap);
        // Il recupero nasce da quando la serie è finita: ne restano 90 secondi,
        // non 120, anche se l'app si è svegliata solo adesso.
        expect(timerEngine.current!.startedAt, tap);
        expect(timerEngine.current!.remaining, const Duration(seconds: 90));

        await bloc.close();
      },
    );

    test('la stessa conferma consegnata due volte vale una', () async {
      final bloc = await startedSession();
      final tap = _now.subtract(const Duration(seconds: 5));

      live.deliver(setConfirmed(bloc, at: tap));
      live.deliver(setConfirmed(bloc, at: tap));
      await pumpEventQueue();

      expect(bloc.state.items.first.entry.sets, hasLength(1));

      await bloc.close();
    });

    test('una conferma di un\'altra sessione viene scartata', () async {
      final bloc = await startedSession();

      live.deliver(setConfirmed(bloc, at: _now, logId: 999));
      await pumpEventQueue();

      expect(bloc.state.items.first.entry.sets, isEmpty);

      await bloc.close();
    });

    test(
      'un recupero già scaduto non fa partire un timer nato morto',
      () async {
        final bloc = await startedSession();

        live.deliver(
          setConfirmed(bloc, at: _now.subtract(const Duration(minutes: 5))),
        );
        await pumpEventQueue();

        expect(bloc.state.items.first.entry.sets, hasLength(1));
        expect(timerEngine.current, isNull);

        await bloc.close();
      },
    );

    test(
      'al rientro in primo piano la coda del nativo viene drenata',
      () async {
        final bloc = await startedSession();
        final tap = _now.subtract(const Duration(seconds: 10));
        live.pending = [setConfirmed(bloc, at: tap)];

        bloc.add(const AppLifecycleChanged(toBackground: false));
        await pumpEventQueue();

        expect(bloc.state.items.first.entry.sets.single.completedAt, tap);

        await bloc.close();
      },
    );

    test(
      'alla riapertura della sessione la coda del nativo viene drenata',
      () async {
        // Processo ucciso durante l'allenamento: la conferma è rimasta in
        // coda e al rientro nessun cambio di lifecycle arriva mai, perché il
        // Bloc nasce adesso.
        final plan = plans.plans[1]!;
        final day = plan.days.first;
        final log = WorkoutLog.start(
          startedAt: _now,
          planNameSnapshot: plan.name,
          dayLabelSnapshot: day.label,
        );
        log.plan.target = plan;
        log.day.target = day;
        log.entries.addAll([
          LogEntry(exerciseNameSnapshot: 'Panca piana', sortOrder: 0),
          LogEntry(exerciseNameSnapshot: 'Rematore', sortOrder: 1),
        ]);
        final logId = logs.saveLog(log);

        final tap = _now.subtract(const Duration(seconds: 10));
        live.pending = [
          LiveSessionAction(
            id: 'azione-1',
            kind: LiveSessionActionKind.setCompleted,
            logId: logId,
            entryIndex: 0,
            setNumber: 1,
            at: tap,
          ),
        ];

        final bloc = buildBloc()..add(SessionResumed(logId));
        await pumpEventQueue();

        expect(bloc.state.items.first.entry.sets.single.completedAt, tap);

        await bloc.close();
      },
    );

    test(
      'con l\'evidenza sul secondo della coppia il banner resta sul giro',
      () async {
        final bloc = await startedSession(dayId: 11);

        bloc.add(const ExerciseFocused(1));
        await pumpEventQueue();

        expect(live.last!.exerciseName, 'Curl EZ + French press');
        // L'azione si riconosce dal primo esercizio del gruppo.
        expect(live.last!.entryIndex, 0);
        expect(live.last!.restSecondsOnComplete, 60);

        await bloc.close();
      },
    );

    test('a recupero scaduto la superficie dice che è finito', () async {
      final bloc = await startedSession();

      // Timer nato già scaduto: è la forma in cui si vede la transizione
      // senza dover far scorrere l'orologio del test.
      bloc.add(
        TimerRequested(
          TimerSpec.rest(const Duration(minutes: 2)),
          startedAt: _now.subtract(const Duration(minutes: 5)),
        ),
      );
      await pumpEventQueue();

      expect(live.last!.countdownEndsAt, isNull);
      expect(live.last!.countdownLabel, 'Recupero finito');

      await bloc.close();
    });

    test('chiudendo la sessione la superficie si spegne', () async {
      final bloc = await startedSession();

      bloc.add(const SessionFinished(status: WorkoutStatus.completed));
      await pumpEventQueue();

      expect(live.stopCount, greaterThan(0));

      await bloc.close();
    });
  });
}
