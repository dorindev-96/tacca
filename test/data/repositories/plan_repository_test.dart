import 'dart:io';

import 'package:tacca/data/db/object_box.dart';
import 'package:tacca/data/entities/block.dart';
import 'package:tacca/data/entities/exercise.dart';
import 'package:tacca/data/entities/workout_day.dart';
import 'package:tacca/data/entities/workout_log.dart';
import 'package:tacca/data/entities/workout_plan.dart';
import 'package:tacca/data/repositories/plan_repository.dart';
import 'package:tacca/objectbox.g.dart';
import 'package:flutter_test/flutter_test.dart';

import '../objectbox_test_support.dart';

void main() {
  final skip = objectBoxNativeLibSkipReason();

  group('ObjectBoxPlanRepository', () {
    late Directory tempDir;
    late ObjectBox obx;
    late PlanRepository repository;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('obx-plan-repo-test-');
      final store = Store(getObjectBoxModel(), directory: tempDir.path);
      obx = ObjectBox.fromStore(store);
      repository = ObjectBoxPlanRepository(obx);
    });

    tearDown(() {
      obx.close();
      tempDir.deleteSync(recursive: true);
    });

    WorkoutPlan buildPlan({
      String name = 'Push / Pull / Legs',
      bool isArchived = false,
      bool isActive = false,
    }) {
      final now = DateTime(2026, 1, 1);
      return WorkoutPlan(
        name: name,
        createdAt: now,
        updatedAt: now,
        isArchived: isArchived,
        isActive: isActive,
      );
    }

    WorkoutDay buildDayWithContent({
      int sortOrder = 0,
      String label = 'Giorno A',
    }) {
      final day = WorkoutDay(label: label, sortOrder: sortOrder);
      final block = Block.ofType(BlockType.standard, sortOrder: 0);
      block.exercises.add(Exercise(name: 'Panca piana', sets: 4, reps: '8-12'));
      day.blocks.add(block);
      return day;
    }

    test(
      'savePlan inserisce e getById restituisce la scheda con id assegnato',
      () {
        final plan = buildPlan();
        final id = repository.savePlan(plan);

        expect(id, greaterThan(0));
        final loaded = repository.getById(id);
        expect(loaded, isNotNull);
        expect(loaded!.name, 'Push / Pull / Legs');
      },
    );

    test('savePlan su una scheda esistente aggiorna updatedAt', () {
      final plan = buildPlan();
      repository.savePlan(plan);
      // Il riferimento va riletto dal database e non preso da `plan`:
      // `PropertyType.date` salva al millisecondo, mentre in memoria
      // `DateTime.now()` ha i microsecondi. Con due salvataggi nello stesso
      // millisecondo il valore riletto risultava *prima* di quello in memoria.
      final originalUpdatedAt = repository.getById(plan.id)!.updatedAt;

      plan.name = 'Nome aggiornato';
      repository.savePlan(plan);

      final reloaded = repository.getById(plan.id)!;
      expect(reloaded.name, 'Nome aggiornato');
      expect(
        reloaded.updatedAt.isAtSameMomentAs(originalUpdatedAt) ||
            reloaded.updatedAt.isAfter(originalUpdatedAt),
        isTrue,
      );
    });

    test(
      'getById restituisce giorni/blocchi/esercizi già ordinati per sortOrder',
      () {
        final plan = buildPlan();
        // Inseriti volutamente fuori ordine.
        plan.days.add(WorkoutDay(label: 'Giorno B', sortOrder: 1));
        plan.days.add(WorkoutDay(label: 'Giorno A', sortOrder: 0));
        final id = repository.savePlan(plan);

        final loaded = repository.getById(id)!;
        expect(loaded.days.map((d) => d.label).toList(), [
          'Giorno A',
          'Giorno B',
        ]);
      },
    );

    test('watchActive esclude le schede archiviate', () async {
      final active = buildPlan(name: 'Attiva');
      final archived = buildPlan(name: 'Archiviata', isArchived: true);
      repository.savePlan(active);
      repository.savePlan(archived);

      final result = await repository.watchActive().first;
      expect(result.map((p) => p.name), ['Attiva']);
    });

    test('watchArchived restituisce solo le schede archiviate', () async {
      final active = buildPlan(name: 'Attiva');
      final archived = buildPlan(name: 'Archiviata', isArchived: true);
      repository.savePlan(active);
      repository.savePlan(archived);

      final result = await repository.watchArchived().first;
      expect(result.map((p) => p.name), ['Archiviata']);
    });

    test('setActivePlan garantisce una sola scheda "in uso" alla volta', () {
      final planA = buildPlan(name: 'A', isActive: true);
      final planB = buildPlan(name: 'B');
      final idA = repository.savePlan(planA);
      final idB = repository.savePlan(planB);

      repository.setActivePlan(idB);

      expect(repository.getById(idA)!.isActive, isFalse);
      expect(repository.getById(idB)!.isActive, isTrue);
      expect(repository.getActivePlan()?.id, idB);
    });

    test('setActivePlan su scheda archiviata la ripristina', () {
      final plan = buildPlan(isArchived: true);
      final id = repository.savePlan(plan);

      repository.setActivePlan(id);

      final reloaded = repository.getById(id)!;
      expect(reloaded.isActive, isTrue);
      expect(reloaded.isArchived, isFalse);
    });

    test('clearActivePlan rimuove lo stato "in uso"', () {
      final plan = buildPlan(isActive: true);
      final id = repository.savePlan(plan);

      repository.clearActivePlan();

      expect(repository.getById(id)!.isActive, isFalse);
      expect(repository.getActivePlan(), isNull);
    });

    test('setArchived(true) toglie anche lo stato "in uso"', () {
      final plan = buildPlan(isActive: true);
      final id = repository.savePlan(plan);

      repository.setArchived(id, archived: true);

      final reloaded = repository.getById(id)!;
      expect(reloaded.isArchived, isTrue);
      expect(reloaded.isActive, isFalse);
    });

    test('setArchived(false) ripristina la scheda tra le attive', () {
      final plan = buildPlan(isArchived: true);
      final id = repository.savePlan(plan);

      repository.setArchived(id, archived: false);

      expect(repository.getById(id)!.isArchived, isFalse);
    });

    test(
      'duplicatePlan copia l\'intera struttura senza toccare l\'originale',
      () {
        final plan = buildPlan(name: 'Originale', isActive: true);
        plan.days.add(buildDayWithContent());
        final originalId = repository.savePlan(plan);

        final copyId = repository.duplicatePlan(originalId);

        expect(copyId, isNot(originalId));
        final copy = repository.getById(copyId)!;
        expect(copy.name, 'Originale (copia)');
        expect(copy.isActive, isFalse);
        expect(copy.isArchived, isFalse);
        expect(
          copy.days.single.blocks.single.exercises.single.name,
          'Panca piana',
        );

        // L'originale resta intatto (struttura indipendente, non condivisa).
        final original = repository.getById(originalId)!;
        expect(original.name, 'Originale');
        expect(original.isActive, isTrue);
        expect(
          original.days.single.blocks.single.exercises.single.id,
          isNot(copy.days.single.blocks.single.exercises.single.id),
        );
      },
    );

    test(
      'savePlan persiste le modifiche a giorni, blocchi ed esercizi già salvati',
      () {
        // Regressione: `put` sull'aggregato applica solo le aggiunte/rimozioni
        // pendenti delle ToMany, non le modifiche ai campi dei figli già
        // persistiti. Senza salvataggio esplicito, rinominare un esercizio in
        // una seconda sessione di editor non aveva alcun effetto (RF-02).
        final plan = buildPlan();
        plan.days.add(buildDayWithContent());
        final id = repository.savePlan(plan);

        final reloaded = repository.getById(id)!;
        reloaded.days.first.label = 'Giorno A rinominato';
        reloaded.days.first.blocks.first.notes = 'Note del blocco';
        reloaded.days.first.blocks.first.exercises.first
          ..name = 'Panca inclinata'
          ..load = '75kg';
        repository.savePlan(reloaded);

        final check = repository.getById(id)!;
        expect(check.days.first.label, 'Giorno A rinominato');
        expect(check.days.first.blocks.first.notes, 'Note del blocco');
        expect(
          check.days.first.blocks.first.exercises.first.name,
          'Panca inclinata',
        );
        expect(check.days.first.blocks.first.exercises.first.load, '75kg');
      },
    );

    test('savePlan elimina i figli rimossi dalla bozza', () {
      final plan = buildPlan();
      plan.days.add(buildDayWithContent());
      plan.days.add(buildDayWithContent(sortOrder: 1, label: 'Giorno B'));
      final id = repository.savePlan(plan);
      expect(obx.dayBox.count(), 2);

      final reloaded = repository.getById(id)!;
      reloaded.days.removeAt(1);
      reloaded.days.first.blocks.first.exercises.clear();
      repository.savePlan(reloaded);

      final check = repository.getById(id)!;
      expect(check.days, hasLength(1));
      expect(check.days.first.blocks.first.exercises, isEmpty);
      expect(
        obx.dayBox.count(),
        1,
        reason: 'nessun giorno orfano nel database',
      );
      expect(obx.exerciseBox.count(), 0);
    });

    test(
      'savePlan su una scheda ricaricata con più giorni non perde figli',
      () {
        // getById ordina le ToMany in memoria: l'ordinamento non deve
        // sganciare i figli al salvataggio successivo.
        final plan = buildPlan();
        plan.days.addAll([
          buildDayWithContent(sortOrder: 2, label: 'Giorno C'),
          buildDayWithContent(sortOrder: 0, label: 'Giorno A'),
          buildDayWithContent(sortOrder: 1, label: 'Giorno B'),
        ]);
        final id = repository.savePlan(plan);

        final reloaded = repository.getById(id)!;
        expect(reloaded.days.map((d) => d.label), [
          'Giorno A',
          'Giorno B',
          'Giorno C',
        ]);
        repository.savePlan(reloaded);

        final check = repository.getById(id)!;
        expect(check.days.map((d) => d.label), [
          'Giorno A',
          'Giorno B',
          'Giorno C',
        ]);
        expect(
          check.days.every((d) => d.blocks.single.exercises.length == 1),
          isTrue,
        );
      },
    );

    test('deletePlan rimuove giorni, blocchi ed esercizi collegati', () {
      final plan = buildPlan();
      plan.days.add(buildDayWithContent());
      final id = repository.savePlan(plan);
      final dayId = plan.days.single.id;
      final blockId = plan.days.single.blocks.single.id;
      final exerciseId = plan.days.single.blocks.single.exercises.single.id;

      repository.deletePlan(id);

      expect(repository.getById(id), isNull);
      expect(obx.dayBox.get(dayId), isNull);
      expect(obx.blockBox.get(blockId), isNull);
      expect(obx.exerciseBox.get(exerciseId), isNull);
    });

    test('deletePlan non tocca i log storici collegati (riferimento debole)', () {
      final plan = buildPlan();
      final planId = repository.savePlan(plan);

      final log = WorkoutLog.start(
        startedAt: DateTime(2026, 2, 1),
        planNameSnapshot: plan.name,
        dayLabelSnapshot: 'Giorno A',
      );
      log.plan.target = plan;
      final logId = obx.logBox.put(log);

      repository.deletePlan(planId);

      final reloadedLog = obx.logBox.get(logId)!;
      expect(reloadedLog.planNameSnapshot, 'Push / Pull / Legs');
      expect(reloadedLog.dayLabelSnapshot, 'Giorno A');
      // Riferimento debole: la scheda non esiste più, ma leggere il log non deve fallire.
      expect(reloadedLog.plan.target, isNull);
    });
  }, skip: skip);
}
