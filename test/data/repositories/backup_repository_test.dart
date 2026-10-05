import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tacca/data/db/object_box.dart';
import 'package:tacca/data/entities/block.dart';
import 'package:tacca/data/entities/exercise.dart';
import 'package:tacca/data/entities/log_entry.dart';
import 'package:tacca/data/entities/log_set.dart';
import 'package:tacca/data/entities/workout_day.dart';
import 'package:tacca/data/entities/workout_log.dart';
import 'package:tacca/data/entities/workout_plan.dart';
import 'package:tacca/data/repositories/backup_repository.dart';
import 'package:tacca/data/repositories/plan_repository.dart';
import 'package:tacca/data/repositories/workout_log_repository.dart';
import 'package:tacca/objectbox.g.dart';

import '../objectbox_test_support.dart';

void main() {
  final skip = objectBoxNativeLibSkipReason();

  group('ObjectBoxBackupRepository', () {
    late Directory tempDir;
    late ObjectBox obx;
    late BackupRepository backup;
    late PlanRepository plans;
    late WorkoutLogRepository logs;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('obx-backup-repo-test-');
      obx = ObjectBox.fromStore(
        Store(getObjectBoxModel(), directory: tempDir.path),
      );
      backup = ObjectBoxBackupRepository(obx);
      plans = ObjectBoxPlanRepository(obx);
      logs = ObjectBoxWorkoutLogRepository(obx);
    });

    tearDown(() {
      obx.close();
      tempDir.deleteSync(recursive: true);
    });

    /// Una scheda nuova, non ancora nel database, con [exercises] esercizi
    /// scritti in ordine inverso: il repository deve restituirli ordinati.
    WorkoutPlan newPlan(String name, {int exercises = 2}) {
      final now = DateTime(2026, 5, 1);
      final plan = WorkoutPlan(name: name, createdAt: now, updatedAt: now);
      final day = WorkoutDay(label: 'Giorno A');
      final block = Block.ofType(BlockType.standard);
      for (var i = exercises - 1; i >= 0; i--) {
        block.exercises.add(Exercise(name: '$name $i', sortOrder: i));
      }
      day.blocks.add(block);
      plan.days.add(day);
      return plan;
    }

    WorkoutLog newLog(WorkoutPlan plan, {required DateTime startedAt}) {
      final log = WorkoutLog(
        startedAt: startedAt,
        finishedAt: startedAt.add(const Duration(hours: 1)),
        dbStatus: WorkoutStatus.completed.name,
        planNameSnapshot: plan.name,
        dayLabelSnapshot: plan.days.first.label,
      );
      log.plan.target = plan;
      log.day.target = plan.days.first;
      final entry = LogEntry(exerciseNameSnapshot: '${plan.name} 0');
      entry.sets.add(LogSet(setNumber: 1, completedAt: startedAt));
      log.entries.add(entry);
      return log;
    }

    test('readAll restituisce tutto, archiviate e sessione aperta comprese, '
        'con gli alberi ordinati', () {
      final active = plans.savePlan(newPlan('Attiva', exercises: 3));
      final archived = plans.savePlan(newPlan('Archiviata'));
      plans.setArchived(archived, archived: true);
      final saved = plans.getById(active)!;
      logs.startSession(plan: saved, day: saved.days.first);

      final data = backup.readAll();

      expect(data.plans.map((p) => p.name), ['Attiva', 'Archiviata']);
      expect(
        data.plans.first.days.single.blocks.single.exercises.map((e) => e.name),
        ['Attiva 0', 'Attiva 1', 'Attiva 2'],
      );
      expect(data.logs.single.status, WorkoutStatus.inProgress);
      expect(backup.count(), (plans: 2, logs: 1));
    }, skip: skip);

    test('replaceAll sostituisce tutto e ricollega gli allenamenti alle '
        'schede nuove', () {
      plans.savePlan(newPlan('Di prima'));
      final oldPlan = plans.getById(plans.savePlan(newPlan('Anche questa')))!;
      logs.startSession(plan: oldPlan, day: oldPlan.days.first);

      final first = newPlan('Dal backup 1');
      final second = newPlan('Dal backup 2');
      backup.replaceAll(
        BackupData(
          plans: [first, second],
          logs: [
            newLog(second, startedAt: DateTime(2026, 6, 1)),
            newLog(first, startedAt: DateTime(2026, 6, 2)),
          ],
        ),
      );

      final data = backup.readAll();
      expect(data.plans.map((p) => p.name), ['Dal backup 1', 'Dal backup 2']);
      expect(logs.findInProgress(), isNull);
      // Gli allenamenti puntano agli id che le schede hanno preso adesso.
      final [june1, june2] = data.logs;
      expect(june1.plan.target?.name, 'Dal backup 2');
      expect(june1.day.target?.id, data.plans.last.days.single.id);
      expect(june2.plan.target?.name, 'Dal backup 1');
      expect(june1.entries.single.sets, hasLength(1));
      // Niente orfani: dei vecchi alberi non resta una riga.
      expect(obx.dayBox.count(), 2);
      expect(obx.exerciseBox.count(), 4);
      expect(obx.logEntryBox.count(), 2);
    }, skip: skip);
  });
}
