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
      'senza recupero del giro il nativo non avvia nessun countdown',
      () async {
        // Giorno a superset: il riposo è del giro, quindi nasce solo
        // dall'ultimo esercizio del blocco.
        final bloc = await startedSession(dayId: 11);

        expect(live.started.single.restSecondsOnComplete, 0);

        bloc.add(const ExerciseFocused(1));
        await pumpEventQueue();

        expect(live.last!.exerciseName, 'French press');
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
