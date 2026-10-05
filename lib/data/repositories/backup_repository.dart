import 'package:tacca/objectbox.g.dart';

import '../db/object_box.dart';
import '../entities/workout_log.dart';
import '../entities/workout_plan.dart';
import 'plan_repository.dart';
import 'workout_log_repository.dart';

/// Tutto ciò che l'utente ha scritto nell'app, come entra in un backup e ne
/// esce: le schede, archiviate comprese, e gli allenamenti, ognuno con il suo
/// albero completo e già ordinato.
///
/// Gli allenamenti si riferiscono alle schede e ai giorni **di questo stesso
/// contenuto** (`log.plan.target`, `log.day.target`): restano gli stessi
/// riferimenti deboli del database, e un allenamento la cui scheda è stata
/// eliminata non ne ha.
class BackupData {
  const BackupData({required this.plans, required this.logs});

  final List<WorkoutPlan> plans;
  final List<WorkoutLog> logs;
}

/// Lettura e sostituzione dell'archivio intero, per il backup locale.
///
/// È un repository a sé, e non due metodi in più su [PlanRepository] e
/// [WorkoutLogRepository], perché il ripristino tocca schede e allenamenti
/// **nella stessa transazione**: un backup si applica tutto o niente, mai un
/// archivio con le schede nuove e lo storico vecchio.
abstract interface class BackupRepository {
  /// Tutte le schede e tutti gli allenamenti, sessione aperta compresa.
  BackupData readAll();

  /// Quante schede e quanti allenamenti ci sono adesso: è ciò che un
  /// ripristino sostituirebbe, e l'utente deve saperlo prima di confermare.
  ({int plans, int logs}) count();

  /// Sostituisce l'intero archivio con [data], in una sola transazione.
  ///
  /// [data] è fatto di oggetti nuovi (id 0): ognuno prende un id nuovo, e i
  /// riferimenti dagli allenamenti alle schede si ricollegano da sé perché
  /// puntano agli oggetti, non agli id.
  void replaceAll(BackupData data);
}

class ObjectBoxBackupRepository implements BackupRepository {
  ObjectBoxBackupRepository(this._objectBox);

  final ObjectBox _objectBox;

  @override
  BackupData readAll() {
    final plans = _objectBox.planBox.getAll()..forEach(sortPlanTree);
    final logs = _objectBox.logBox.getAll()
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt))
      ..forEach(sortLogTree);
    return BackupData(plans: plans, logs: logs);
  }

  @override
  ({int plans, int logs}) count() =>
      (plans: _objectBox.planBox.count(), logs: _objectBox.logBox.count());

  @override
  void replaceAll(BackupData data) {
    _objectBox.store.runInTransaction(TxMode.write, () {
      _objectBox.logSetBox.removeAll();
      _objectBox.logEntryBox.removeAll();
      _objectBox.logBox.removeAll();
      _objectBox.exerciseBox.removeAll();
      _objectBox.blockBox.removeAll();
      _objectBox.dayBox.removeAll();
      _objectBox.planBox.removeAll();

      // Come in `savePlan` e `saveLog`: ogni figlio si salva esplicitamente,
      // senza contare sulla cascata di `put`. Le schede prima degli
      // allenamenti, perché i riferimenti di questi trovino un id.
      for (final plan in data.plans) {
        _putPlan(plan);
      }
      for (final log in data.logs) {
        _putLog(log);
      }
    });
  }

  void _putPlan(WorkoutPlan plan) {
    _objectBox.planBox.put(plan);
    for (final day in plan.days) {
      day.plan.target = plan;
      _objectBox.dayBox.put(day);
      for (final block in day.blocks) {
        block.day.target = day;
        _objectBox.blockBox.put(block);
        for (final exercise in block.exercises) {
          exercise.block.target = block;
          _objectBox.exerciseBox.put(exercise);
        }
      }
    }
  }

  void _putLog(WorkoutLog log) {
    _objectBox.logBox.put(log);
    for (final entry in log.entries) {
      entry.log.target = log;
      _objectBox.logEntryBox.put(entry);
      for (final set in entry.sets) {
        set.entry.target = entry;
        _objectBox.logSetBox.put(set);
      }
    }
  }
}
