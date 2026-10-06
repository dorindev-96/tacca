import 'package:tacca/objectbox.g.dart';

import '../db/object_box.dart';
import '../entities/block.dart';
import '../entities/exercise.dart';
import '../entities/workout_day.dart';
import '../entities/workout_plan.dart';

/// Accesso alle schede di allenamento (RF-01, RF-02).
///
/// Interfaccia astratta: Cubit/Bloc dipendono da questa, mai da [ObjectBox]
/// direttamente (ADR-01).
abstract interface class PlanRepository {
  /// Schede non archiviate, più recenti prima. Si aggiorna ad ogni scrittura.
  Stream<List<WorkoutPlan>> watchActive();

  /// Schede archiviate, stesso ordinamento di [watchActive].
  Stream<List<WorkoutPlan>> watchArchived();

  /// Scheda completa con giorni/blocchi/esercizi già ordinati per `sortOrder`.
  WorkoutPlan? getById(int id);

  /// La scheda marcata "in uso", se presente.
  WorkoutPlan? getActivePlan();

  /// Inserisce o aggiorna l'intera struttura (cascata via `ToMany`),
  /// aggiornando `updatedAt`. Ritorna l'id della scheda.
  int savePlan(WorkoutPlan plan);

  /// Marca [planId] come "in uso": smarca ogni altra scheda eventualmente attiva.
  void setActivePlan(int planId);

  /// Rimuove lo stato "in uso" dalla scheda che lo detiene, se esiste.
  void clearActivePlan();

  /// Archivia o ripristina una scheda. L'archiviazione toglie anche lo stato "in uso".
  void setArchived(int planId, {required bool archived});

  /// Copia l'intera struttura (non i log, non lo stato in uso/archiviata).
  /// Ritorna l'id della nuova scheda.
  int duplicatePlan(int planId);

  /// Elimina la scheda e l'intera struttura (giorni/blocchi/esercizi).
  /// I log storici collegati restano intatti: riferimento debole (§4).
  void deletePlan(int planId);
}

class ObjectBoxPlanRepository implements PlanRepository {
  ObjectBoxPlanRepository(this._objectBox);

  final ObjectBox _objectBox;

  Box<WorkoutPlan> get _planBox => _objectBox.planBox;
  Box<WorkoutDay> get _dayBox => _objectBox.dayBox;
  Box<Block> get _blockBox => _objectBox.blockBox;
  Box<Exercise> get _exerciseBox => _objectBox.exerciseBox;

  @override
  Stream<List<WorkoutPlan>> watchActive() => _watchByArchived(archived: false);

  @override
  Stream<List<WorkoutPlan>> watchArchived() => _watchByArchived(archived: true);

  Stream<List<WorkoutPlan>> _watchByArchived({required bool archived}) {
    return (_planBox.query(WorkoutPlan_.isArchived.equals(archived))
          ..order(WorkoutPlan_.updatedAt, flags: Order.descending))
        .watch(triggerImmediately: true)
        .map((query) => query.find()..forEach(sortPlanTree));
  }

  @override
  WorkoutPlan? getById(int id) {
    final plan = _planBox.get(id);
    if (plan != null) sortPlanTree(plan);
    return plan;
  }

  @override
  WorkoutPlan? getActivePlan() {
    final query = _planBox.query(WorkoutPlan_.isActive.equals(true)).build();
    try {
      final plan = query.findFirst();
      if (plan != null) sortPlanTree(plan);
      return plan;
    } finally {
      query.close();
    }
  }

  @override
  int savePlan(WorkoutPlan plan) {
    return _objectBox.store.runInTransaction(TxMode.write, () {
      // Ids dei figli attualmente persistiti: quelli che non ricompaiono
      // nell'albero in memoria sono stati rimossi dalla bozza.
      final staleDayIds = <int>{};
      final staleBlockIds = <int>{};
      final staleExerciseIds = <int>{};
      if (plan.id != 0) {
        final persisted = _planBox.get(plan.id);
        for (final day in persisted?.days ?? const <WorkoutDay>[]) {
          staleDayIds.add(day.id);
          for (final block in day.blocks) {
            staleBlockIds.add(block.id);
            staleExerciseIds.addAll(block.exercises.map((e) => e.id));
          }
        }
      }

      plan.updatedAt = DateTime.now();
      final planId = _planBox.put(plan);

      // `put` sull'aggregato applica solo le aggiunte/rimozioni pendenti delle
      // `ToMany` (`ToMany.applyToDb`): le modifiche ai campi di figli **già
      // persistiti** non vengono propagate. Vanno quindi salvati esplicitamente,
      // altrimenti rinominare un esercizio esistente non avrebbe alcun effetto.
      for (final day in plan.days) {
        day.plan.target = plan;
        _dayBox.put(day);
        staleDayIds.remove(day.id);
        for (final block in day.blocks) {
          block.day.target = day;
          _blockBox.put(block);
          staleBlockIds.remove(block.id);
          for (final exercise in block.exercises) {
            exercise.block.target = block;
            _exerciseBox.put(exercise);
            staleExerciseIds.remove(exercise.id);
          }
        }
      }

      // Senza questa pulizia i figli rimossi resterebbero nel DB con il
      // riferimento al padre azzerato (orfani invisibili ma persistenti).
      if (staleExerciseIds.isNotEmpty) {
        _exerciseBox.removeMany(staleExerciseIds.toList());
      }
      if (staleBlockIds.isNotEmpty) {
        _blockBox.removeMany(staleBlockIds.toList());
      }
      if (staleDayIds.isNotEmpty) _dayBox.removeMany(staleDayIds.toList());

      return planId;
    });
  }

  @override
  void setActivePlan(int planId) {
    _objectBox.store.runInTransaction(TxMode.write, () {
      final query = _planBox.query(WorkoutPlan_.isActive.equals(true)).build();
      final currentlyActive = query.find();
      query.close();

      final toUpdate = <WorkoutPlan>[
        for (final plan in currentlyActive)
          if (plan.id != planId) (plan..isActive = false),
      ];

      final target = _planBox.get(planId);
      if (target != null) {
        target
          ..isActive = true
          ..isArchived = false;
        toUpdate.add(target);
      }
      if (toUpdate.isNotEmpty) _planBox.putMany(toUpdate);
    });
  }

  @override
  void clearActivePlan() {
    final query = _planBox.query(WorkoutPlan_.isActive.equals(true)).build();
    final active = query.find();
    query.close();
    if (active.isEmpty) return;
    for (final plan in active) {
      plan.isActive = false;
    }
    _planBox.putMany(active);
  }

  @override
  void setArchived(int planId, {required bool archived}) {
    final plan = _planBox.get(planId);
    if (plan == null) return;
    plan.isArchived = archived;
    if (archived) plan.isActive = false;
    plan.updatedAt = DateTime.now();
    _planBox.put(plan);
  }

  @override
  int duplicatePlan(int planId) {
    final source = getById(planId);
    if (source == null) {
      throw ArgumentError.value(planId, 'planId', 'Scheda non trovata');
    }

    final now = DateTime.now();
    final copy = WorkoutPlan(
      name: '${source.name} (copia)',
      description: source.description,
      notes: source.notes,
      createdAt: now,
      updatedAt: now,
      imagePaths: List.of(source.imagePaths),
    );

    for (final day in source.days) {
      final dayCopy = WorkoutDay(
        label: day.label,
        notes: day.notes,
        sortOrder: day.sortOrder,
      );
      for (final block in day.blocks) {
        final blockCopy =
            Block(
                dbType: block.dbType,
                sortOrder: block.sortOrder,
                notes: block.notes,
              )
              ..intervalSeconds = block.intervalSeconds
              ..totalMinutes = block.totalMinutes
              ..durationSeconds = block.durationSeconds
              ..workSeconds = block.workSeconds
              ..restSeconds = block.restSeconds
              ..rounds = block.rounds
              ..restBetweenRoundsSeconds = block.restBetweenRoundsSeconds
              ..timeCapSeconds = block.timeCapSeconds
              ..freeTextContent = block.freeTextContent;
        for (final exercise in block.exercises) {
          blockCopy.exercises.add(
            Exercise(
              name: exercise.name,
              sets: exercise.sets,
              reps: exercise.reps,
              load: exercise.load,
              restSeconds: exercise.restSeconds,
              durationSeconds: exercise.durationSeconds,
              notes: exercise.notes,
              sortOrder: exercise.sortOrder,
            ),
          );
        }
        dayCopy.blocks.add(blockCopy);
      }
      copy.days.add(dayCopy);
    }

    return _planBox.put(copy);
  }

  @override
  void deletePlan(int planId) {
    _objectBox.store.runInTransaction(TxMode.write, () {
      final plan = _planBox.get(planId);
      if (plan == null) return;

      for (final day in plan.days) {
        for (final block in day.blocks) {
          final exerciseIds = block.exercises.map((e) => e.id).toList();
          if (exerciseIds.isNotEmpty) _exerciseBox.removeMany(exerciseIds);
        }
        final blockIds = day.blocks.map((b) => b.id).toList();
        if (blockIds.isNotEmpty) _blockBox.removeMany(blockIds);
      }
      final dayIds = plan.days.map((d) => d.id).toList();
      if (dayIds.isNotEmpty) _dayBox.removeMany(dayIds);

      _planBox.remove(planId);
    });
  }
}

/// Ordina in memoria l'intero albero di [plan] per `sortOrder` (§4: i
/// repository restituiscono liste già ordinate; `ToMany` non garantisce
/// l'ordine).
///
/// È una funzione e non un metodo perché le schede non escono solo da qui:
/// anche il backup le legge tutte insieme, e deve leggerle nello stesso
/// ordine.
void sortPlanTree(WorkoutPlan plan) {
  plan.days.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  for (final day in plan.days) {
    day.blocks.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    for (final block in day.blocks) {
      block.exercises.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    }
  }
}
