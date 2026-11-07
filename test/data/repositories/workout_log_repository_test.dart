import 'dart:io';

import 'package:tacca/data/db/object_box.dart';
import 'package:tacca/data/entities/block.dart';
import 'package:tacca/data/entities/exercise.dart';
import 'package:tacca/data/entities/log_set.dart';
import 'package:tacca/data/entities/workout_day.dart';
import 'package:tacca/data/entities/workout_log.dart';
import 'package:tacca/data/entities/workout_plan.dart';
import 'package:tacca/data/repositories/plan_repository.dart';
import 'package:tacca/data/repositories/workout_log_repository.dart';
import 'package:tacca/objectbox.g.dart';
import 'package:flutter_test/flutter_test.dart';

import '../objectbox_test_support.dart';

void main() {
  final skip = objectBoxNativeLibSkipReason();

  group('ObjectBoxWorkoutLogRepository', () {
    late Directory tempDir;
    late ObjectBox obx;
    late PlanRepository plans;
    late WorkoutLogRepository logs;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('obx-log-repo-test-');
      final store = Store(getObjectBoxModel(), directory: tempDir.path);
      obx = ObjectBox.fromStore(store);
      plans = ObjectBoxPlanRepository(obx);
      logs = ObjectBoxWorkoutLogRepository(obx);
    });

    tearDown(() {
      obx.close();
      tempDir.deleteSync(recursive: true);
    });

    /// Scheda a un giorno con due blocchi: tre esercizi in tutto, più un
    /// blocco `freeText` che non deve generare entry.
    (WorkoutPlan, WorkoutDay) seedPlan() {
      final now = DateTime(2026, 8, 1);
      final plan = WorkoutPlan(
        name: 'Upper / Lower',
        createdAt: now,
        updatedAt: now,
      );
      final day = WorkoutDay(label: 'Giorno A', sortOrder: 0);

      final first = Block.ofType(BlockType.standard, sortOrder: 0);
      first.exercises.add(
        Exercise(name: 'Panca piana', sets: 3, reps: '8', sortOrder: 0),
      );
      first.exercises.add(
        Exercise(name: 'Rematore', sets: 3, reps: '10', sortOrder: 1),
      );

      final second = Block.ofType(BlockType.emom, sortOrder: 1)
        ..intervalSeconds = 60
        ..totalMinutes = 10;
      second.exercises.add(Exercise(name: 'Trazioni', reps: '5', sortOrder: 0));

      final free = Block.ofType(BlockType.freeText, sortOrder: 2)
        ..freeTextContent = 'Finisher a scelta';

      day.blocks.addAll([first, second, free]);
      plan.days.add(day);
      plans.savePlan(plan);

      final saved = plans.getById(plan.id)!;
      return (saved, saved.days.first);
    }

    test(
      'startSession crea una entry per esercizio, nell\'ordine del giorno',
      () {
        final (plan, day) = seedPlan();

        final log = logs.startSession(plan: plan, day: day);

        expect(log.id, greaterThan(0));
        expect(log.status, WorkoutStatus.inProgress);
        expect(log.planNameSnapshot, 'Upper / Lower');
        expect(log.dayLabelSnapshot, 'Giorno A');
        expect(log.plan.targetId, plan.id);
        expect(log.day.targetId, day.id);

        final reloaded = logs.getById(log.id)!;
        expect(reloaded.entries.map((e) => e.exerciseNameSnapshot), [
          'Panca piana',
          'Rematore',
          'Trazioni',
        ]);
        expect(reloaded.entries.map((e) => e.sortOrder), [0, 1, 2]);
      },
      skip: skip,
    );

    test(
      'saveLog persiste le modifiche alle serie già salvate (autosave)',
      () {
        final (plan, day) = seedPlan();
        final log = logs.startSession(plan: plan, day: day);

        // Prima spunta: la serie nasce adesso.
        log.entries.first.sets.add(
          LogSet(setNumber: 1, reps: '8', completedAt: DateTime(2026, 8, 15)),
        );
        logs.saveLog(log);

        // Correzione del peso su una serie GIÀ persistita: è il caso in cui
        // ObjectBox non propaga in cascata e serve il salvataggio esplicito.
        final loaded = logs.getById(log.id)!;
        loaded.entries.first.sets.first
          ..weightKg = 82.5
          ..reps = '7';
        logs.saveLog(loaded);

        final check = logs.getById(log.id)!;
        expect(check.entries.first.sets.first.weightKg, 82.5);
        expect(check.entries.first.sets.first.reps, '7');
      },
      skip: skip,
    );

    test('saveLog elimina le serie tolte dalla spunta', () {
      final (plan, day) = seedPlan();
      final log = logs.startSession(plan: plan, day: day);
      final entry = log.entries.first;
      entry.sets.addAll([
        LogSet(setNumber: 1, completedAt: DateTime(2026, 8, 15)),
        LogSet(setNumber: 2, completedAt: DateTime(2026, 8, 15)),
      ]);
      logs.saveLog(log);
      expect(obx.logSetBox.count(), 2);

      final loaded = logs.getById(log.id)!;
      loaded.entries.first.sets.removeWhere((s) => s.setNumber == 2);
      logs.saveLog(loaded);

      final check = logs.getById(log.id)!;
      expect(check.entries.first.sets.map((s) => s.setNumber), [1]);
      expect(
        obx.logSetBox.count(),
        1,
        reason: 'la serie rimossa non deve restare orfana nel database',
      );
    }, skip: skip);

    test('findInProgress restituisce solo la sessione ancora aperta', () {
      final (plan, day) = seedPlan();
      expect(logs.findInProgress(), isNull);

      final log = logs.startSession(plan: plan, day: day);
      expect(logs.findInProgress()?.id, log.id);

      log
        ..status = WorkoutStatus.completed
        ..finishedAt = DateTime(2026, 8, 15, 19);
      logs.saveLog(log);

      expect(logs.findInProgress(), isNull);
    }, skip: skip);

    test(
      'startSession chiude quella rimasta aperta: una sessione per volta',
      () {
        final (plan, day) = seedPlan();

        final first = logs.startSession(
          plan: plan,
          day: day,
          startedAt: DateTime(2026, 8, 14, 18),
        );
        // Serie registrate nella sessione che sta per essere chiusa: devono
        // sopravvivere: interrotta non vuol dire cancellata (RF-07).
        first.entries.first.sets.add(
          LogSet(setNumber: 1, reps: '8', completedAt: DateTime(2026, 8, 14)),
        );
        logs.saveLog(first);

        final second = logs.startSession(
          plan: plan,
          day: day,
          startedAt: DateTime(2026, 8, 15, 18),
        );

        final closed = logs.getById(first.id)!;
        expect(closed.status, WorkoutStatus.aborted);
        expect(closed.finishedAt, second.startedAt);
        expect(closed.entries.first.sets, hasLength(1));

        // Ne resta aperta una sola, ed è quella appena iniziata.
        expect(logs.findInProgress()?.id, second.id);
      },
      skip: skip,
    );

    test('watchInProgress segue apertura e chiusura della sessione', () async {
      final (plan, day) = seedPlan();
      final emissions = <int?>[];
      final subscription = logs.watchInProgress().listen(
        (log) => emissions.add(log?.id),
      );
      addTearDown(subscription.cancel);
      await Future<void>.delayed(Duration.zero);

      final log = logs.startSession(plan: plan, day: day);
      await Future<void>.delayed(Duration.zero);

      log
        ..status = WorkoutStatus.completed
        ..finishedAt = DateTime(2026, 8, 15, 19);
      logs.saveLog(log);
      await Future<void>.delayed(Duration.zero);

      // Nessuna sessione → quella aperta → di nuovo nessuna: è ciò che
      // permette alla UI di accorgersene senza riavviare l'app.
      expect(emissions.first, isNull);
      expect(emissions, contains(log.id));
      expect(emissions.last, isNull);
    }, skip: skip);

    test(
      'watchFinished esclude le sessioni in corso, più recenti prima',
      () async {
        final (plan, day) = seedPlan();

        final older = logs.startSession(
          plan: plan,
          day: day,
          startedAt: DateTime(2026, 8, 10, 18),
        );
        older
          ..status = WorkoutStatus.completed
          ..finishedAt = DateTime(2026, 8, 10, 19);
        logs.saveLog(older);

        final newer = logs.startSession(
          plan: plan,
          day: day,
          startedAt: DateTime(2026, 8, 14, 18),
        );
        newer
          ..status = WorkoutStatus.aborted
          ..finishedAt = DateTime(2026, 8, 14, 18, 20);
        logs.saveLog(newer);

        // Ancora aperta: non deve comparire.
        logs.startSession(
          plan: plan,
          day: day,
          startedAt: DateTime(2026, 8, 15, 18),
        );

        final emitted = await logs.watchFinished().first;
        expect(emitted.map((l) => l.id), [newer.id, older.id]);
      },
      skip: skip,
    );

    test(
      'l\'autosave della sessione in corso non riemette storico né sessione aperta',
      () async {
        // Le notifiche di ObjectBox arrivano dal thread nativo: si lascia loro
        // il tempo di arrivare tutte prima di contarle.
        Future<void> settle() =>
            Future<void>.delayed(const Duration(milliseconds: 50));

        final (plan, day) = seedPlan();
        final finished = <List<int>>[];
        final inProgress = <int?>[];
        final finishedSub = logs.watchFinished().listen(
          (list) => finished.add([for (final log in list) log.id]),
        );
        final inProgressSub = logs.watchInProgress().listen(
          (log) => inProgress.add(log?.id),
        );
        addTearDown(finishedSub.cancel);
        addTearDown(inProgressSub.cancel);
        await settle();

        final log = logs.startSession(plan: plan, day: day);
        await settle();
        expect(finished, [<int>[]]);
        expect(inProgress, [null, log.id]);

        // Tre serie spuntate, tre autosave: nessuno cambia i due elenchi.
        for (var n = 1; n <= 3; n++) {
          log.entries.first.sets.add(
            LogSet(setNumber: n, completedAt: DateTime(2026, 8, 15)),
          );
          logs.saveLog(log);
          await settle();
        }
        expect(finished, [<int>[]]);
        expect(inProgress, [null, log.id]);

        // La chiusura invece li cambia entrambi.
        log
          ..status = WorkoutStatus.completed
          ..finishedAt = DateTime(2026, 8, 15, 19);
        logs.saveLog(log);
        await settle();
        expect(finished.last, [log.id]);
        expect(inProgress.last, isNull);

        // E così l'eliminazione dallo storico.
        logs.deleteLog(log.id);
        await settle();
        expect(finished.last, isEmpty);
      },
      skip: skip,
    );

    test(
      'watchInProgress emette la sessione con entry e serie ordinate',
      () async {
        final (plan, day) = seedPlan();
        final log = logs.startSession(plan: plan, day: day);
        log.entries.first.sets.addAll([
          LogSet(setNumber: 2, completedAt: DateTime(2026, 8, 15)),
          LogSet(setNumber: 1, completedAt: DateTime(2026, 8, 15)),
        ]);
        logs.saveLog(log);

        final emitted = await logs.watchInProgress().first;
        expect(emitted?.entries.map((e) => e.exerciseNameSnapshot), [
          'Panca piana',
          'Rematore',
          'Trazioni',
        ]);
        expect(emitted?.entries.first.sets.map((s) => s.setNumber), [1, 2]);
      },
      skip: skip,
    );

    test('deleteLog rimuove entry e serie collegate', () {
      final (plan, day) = seedPlan();
      final log = logs.startSession(plan: plan, day: day);
      log.entries.first.sets.add(
        LogSet(setNumber: 1, completedAt: DateTime(2026, 8, 15)),
      );
      logs.saveLog(log);

      logs.deleteLog(log.id);

      expect(logs.getById(log.id), isNull);
      expect(obx.logEntryBox.count(), 0);
      expect(obx.logSetBox.count(), 0);
    }, skip: skip);

    test(
      'lastPerformance prende l\'ultima sessione conclusa, non quella in corso',
      () {
        final (plan, day) = seedPlan();

        final first = logs.startSession(
          plan: plan,
          day: day,
          startedAt: DateTime(2026, 8, 1, 18),
        );
        first.entries.first.sets.add(
          LogSet(
            setNumber: 1,
            weightKg: 70,
            reps: '8',
            completedAt: DateTime(2026, 8, 1),
          ),
        );
        first
          ..status = WorkoutStatus.completed
          ..finishedAt = DateTime(2026, 8, 1, 19);
        logs.saveLog(first);

        final second = logs.startSession(
          plan: plan,
          day: day,
          startedAt: DateTime(2026, 8, 8, 18),
        );
        second.entries.first.sets.addAll([
          LogSet(
            setNumber: 1,
            weightKg: 75,
            reps: '8',
            completedAt: DateTime(2026, 8, 8),
          ),
          LogSet(
            setNumber: 2,
            weightKg: 75,
            reps: '7',
            completedAt: DateTime(2026, 8, 8),
          ),
        ]);
        second
          ..status = WorkoutStatus.completed
          ..finishedAt = DateTime(2026, 8, 8, 19);
        logs.saveLog(second);

        // Sessione corrente: va esclusa dal confronto "ultima volta".
        final current = logs.startSession(
          plan: plan,
          day: day,
          startedAt: DateTime(2026, 8, 15, 18),
        );
        current.entries.first.sets.add(
          LogSet(
            setNumber: 1,
            weightKg: 80,
            completedAt: DateTime(2026, 8, 15),
          ),
        );
        logs.saveLog(current);

        final last = logs.lastPerformance(
          'Panca piana',
          excludeLogId: current.id,
        );

        expect(last, isNotNull);
        expect(last!.performedAt, DateTime(2026, 8, 8, 18));
        expect(last.sets.map((s) => s.weightKg), [75, 75]);
        expect(last.sets.map((s) => s.setNumber), [1, 2]);
      },
      skip: skip,
    );

    test(
      'lastPerformance salta le sessioni più recenti in cui l\'esercizio non è stato fatto',
      () {
        final (plan, day) = seedPlan();

        final done = logs.startSession(
          plan: plan,
          day: day,
          startedAt: DateTime(2026, 8, 1, 18),
        );
        done.entries.first.sets.add(
          LogSet(setNumber: 1, weightKg: 70, completedAt: DateTime(2026, 8, 1)),
        );
        done
          ..status = WorkoutStatus.completed
          ..finishedAt = DateTime(2026, 8, 1, 19);
        logs.saveLog(done);

        // Più recente, ma la panca non è stata spuntata.
        final skipped = logs.startSession(
          plan: plan,
          day: day,
          startedAt: DateTime(2026, 8, 8, 18),
        );
        skipped
          ..status = WorkoutStatus.aborted
          ..finishedAt = DateTime(2026, 8, 8, 18, 30);
        logs.saveLog(skipped);

        final last = logs.lastPerformance('Panca piana');
        expect(last?.performedAt, DateTime(2026, 8, 1, 18));
        expect(last?.sets.map((s) => s.weightKg), [70]);
      },
      skip: skip,
    );

    test('lastPerformance è nulla senza sessioni precedenti', () {
      final (plan, day) = seedPlan();
      final log = logs.startSession(plan: plan, day: day);

      expect(logs.lastPerformance('Panca piana', excludeLogId: log.id), isNull);
    }, skip: skip);

    test('eliminare la scheda non tocca i log già registrati (RF-01)', () {
      final (plan, day) = seedPlan();
      final log = logs.startSession(plan: plan, day: day);
      log.entries.first.sets.add(
        LogSet(setNumber: 1, weightKg: 60, completedAt: DateTime(2026, 8, 15)),
      );
      log
        ..status = WorkoutStatus.completed
        ..finishedAt = DateTime(2026, 8, 15, 19);
      logs.saveLog(log);

      plans.deletePlan(plan.id);

      final check = logs.getById(log.id)!;
      expect(check.planNameSnapshot, 'Upper / Lower');
      expect(check.entries.first.exerciseNameSnapshot, 'Panca piana');
      expect(check.entries.first.sets.first.weightKg, 60);
      expect(check.plan.target, isNull, reason: 'riferimento debole');
    }, skip: skip);
  });
}
