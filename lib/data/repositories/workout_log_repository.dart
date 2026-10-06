import 'package:tacca/objectbox.g.dart';

import '../db/object_box.dart';
import '../entities/exercise.dart';
import '../entities/log_entry.dart';
import '../entities/log_set.dart';
import '../entities/workout_day.dart';
import '../entities/workout_log.dart';
import '../entities/workout_plan.dart';

/// Ultima prestazione registrata per un esercizio: alimenta l'indicazione
/// "ultima volta" della modalità allenamento (RF-06).
class LastPerformance {
  const LastPerformance({required this.performedAt, required this.sets});

  final DateTime performedAt;

  /// Serie effettivamente registrate, ordinate per `setNumber`.
  final List<LogSet> sets;
}

/// Accesso ai log delle sessioni di allenamento (RF-06, RF-07).
///
/// Interfaccia astratta: il [WorkoutSessionBloc] e [HistoryCubit] dipendono da
/// questa, mai da [ObjectBox] (ADR-01).
abstract interface class WorkoutLogRepository {
  /// Apre una nuova sessione su [day] di [plan] e la persiste subito con stato
  /// `inProgress`: una entry per ogni esercizio prescritto del giorno, nello
  /// stesso ordine in cui compaiono nei blocchi.
  ///
  /// **Una sessione per volta**: se ne esiste un'altra ancora aperta viene
  /// chiusa come interrotta prima di aprire questa. La UI lo chiede
  /// all'utente (RF-06), ma la regola vale comunque, da qualunque strada si
  /// arrivi ad aprire una sessione: due sessioni aperte insieme
  /// significherebbe due autosave concorrenti sullo stesso allenamento.
  WorkoutLog startSession({
    required WorkoutPlan plan,
    required WorkoutDay day,
    DateTime? startedAt,
  });

  /// Sessione rimasta aperta (chiusura o crash dell'app): al più una, la più
  /// recente.
  ///
  /// Lettura sincrona: serve dove la decisione non può aspettare il giro di
  /// [watchInProgress], cioè un istante prima di aprirne un'altra.
  WorkoutLog? findInProgress();

  /// Come [findInProgress], ma osservata: la sessione aperta cambia mentre
  /// l'app è viva — se ne apre una, la si chiude, la si riprende — e le
  /// schermate devono accorgersene senza essere riaperte (§8).
  Stream<WorkoutLog?> watchInProgress();

  /// Log completo con entry e serie già ordinate.
  WorkoutLog? getById(int id);

  /// Sessioni concluse (completate o interrotte), più recenti prima.
  /// Si aggiorna a ogni scrittura.
  Stream<List<WorkoutLog>> watchFinished();

  /// Persiste l'intero albero del log (autosave della sessione, RF-06).
  /// Ritorna l'id del log.
  int saveLog(WorkoutLog log);

  /// Elimina il log con entry e serie collegate (RF-07).
  void deleteLog(int logId);

  /// Serie dell'ultima sessione conclusa in cui compare [exerciseName].
  /// [excludeLogId] esclude la sessione corrente dal confronto.
  LastPerformance? lastPerformance(String exerciseName, {int? excludeLogId});
}

class ObjectBoxWorkoutLogRepository implements WorkoutLogRepository {
  ObjectBoxWorkoutLogRepository(this._objectBox);

  final ObjectBox _objectBox;

  Box<WorkoutLog> get _logBox => _objectBox.logBox;
  Box<LogEntry> get _entryBox => _objectBox.logEntryBox;
  Box<LogSet> get _setBox => _objectBox.logSetBox;

  @override
  WorkoutLog startSession({
    required WorkoutPlan plan,
    required WorkoutDay day,
    DateTime? startedAt,
  }) {
    final start = startedAt ?? DateTime.now();
    // Quella eventualmente rimasta aperta si chiude qui: è l'unico punto da
    // cui nasce una sessione, quindi è il punto in cui "una sola per volta"
    // smette di essere una raccomandazione alla UI.
    _abortOpenSessions(at: start);

    final log = WorkoutLog.start(
      startedAt: start,
      planNameSnapshot: plan.name,
      dayLabelSnapshot: day.label,
    );
    log.plan.target = plan;
    log.day.target = day;

    final exercises = flattenExercises(day);
    for (var i = 0; i < exercises.length; i++) {
      log.entries.add(
        LogEntry(exerciseNameSnapshot: exercises[i].name, sortOrder: i),
      );
    }

    saveLog(log);
    return log;
  }

  @override
  WorkoutLog? findInProgress() {
    final query = (_logBox.query(
      WorkoutLog_.dbStatus.equals(WorkoutStatus.inProgress.name),
    )..order(WorkoutLog_.startedAt, flags: Order.descending)).build();
    try {
      final log = query.findFirst();
      if (log != null) sortLogTree(log);
      return log;
    } finally {
      query.close();
    }
  }

  @override
  Stream<WorkoutLog?> watchInProgress() {
    return (_logBox.query(
          WorkoutLog_.dbStatus.equals(WorkoutStatus.inProgress.name),
        )..order(WorkoutLog_.startedAt, flags: Order.descending))
        .watch(triggerImmediately: true)
        .map((query) {
          final log = query.findFirst();
          if (log != null) sortLogTree(log);
          return log;
        });
  }

  @override
  WorkoutLog? getById(int id) {
    final log = _logBox.get(id);
    if (log != null) sortLogTree(log);
    return log;
  }

  /// Chiude come interrotte le sessioni ancora aperte, datandole [at].
  ///
  /// Interrotte e non eliminate: quello che l'utente ha già registrato resta
  /// nello storico (RF-07). Sono al più una, ma la query le prende tutte —
  /// un database che ne contenesse due deve tornare a posto, non restare
  /// mezzo aperto.
  void _abortOpenSessions({required DateTime at}) {
    _objectBox.store.runInTransaction(TxMode.write, () {
      final query = _logBox
          .query(WorkoutLog_.dbStatus.equals(WorkoutStatus.inProgress.name))
          .build();
      try {
        for (final log in query.find()) {
          log
            ..status = WorkoutStatus.aborted
            ..finishedAt = at;
          _logBox.put(log);
        }
      } finally {
        query.close();
      }
    });
  }

  @override
  Stream<List<WorkoutLog>> watchFinished() {
    return (_logBox.query(
          WorkoutLog_.dbStatus.notEquals(WorkoutStatus.inProgress.name),
        )..order(WorkoutLog_.startedAt, flags: Order.descending))
        .watch(triggerImmediately: true)
        .map((query) => query.find()..forEach(sortLogTree));
  }

  @override
  int saveLog(WorkoutLog log) {
    return _objectBox.store.runInTransaction(TxMode.write, () {
      // Ids dei figli attualmente persistiti: quelli che non ricompaiono
      // nell'albero in memoria sono stati rimossi (spunta tolta a una serie).
      final staleEntryIds = <int>{};
      final staleSetIds = <int>{};
      if (log.id != 0) {
        final persisted = _logBox.get(log.id);
        for (final entry in persisted?.entries ?? const <LogEntry>[]) {
          staleEntryIds.add(entry.id);
          staleSetIds.addAll(entry.sets.map((s) => s.id));
        }
      }

      final logId = _logBox.put(log);

      // Come per le schede: `put` sull'aggregato applica solo aggiunte e
      // rimozioni pendenti della `ToMany`, non le modifiche ai campi dei figli
      // già persistiti. Il salvataggio esplicito è ciò che rende affidabile
      // l'autosave (RF-06: nessun dato perso a crash o chiusura).
      for (final entry in log.entries) {
        entry.log.target = log;
        _entryBox.put(entry);
        staleEntryIds.remove(entry.id);
        for (final set in entry.sets) {
          set.entry.target = entry;
          _setBox.put(set);
          staleSetIds.remove(set.id);
        }
      }

      if (staleSetIds.isNotEmpty) _setBox.removeMany(staleSetIds.toList());
      if (staleEntryIds.isNotEmpty) {
        _entryBox.removeMany(staleEntryIds.toList());
      }

      return logId;
    });
  }

  @override
  void deleteLog(int logId) {
    _objectBox.store.runInTransaction(TxMode.write, () {
      final log = _logBox.get(logId);
      if (log == null) return;

      for (final entry in log.entries) {
        final setIds = entry.sets.map((s) => s.id).toList();
        if (setIds.isNotEmpty) _setBox.removeMany(setIds);
      }
      final entryIds = log.entries.map((e) => e.id).toList();
      if (entryIds.isNotEmpty) _entryBox.removeMany(entryIds);

      _logBox.remove(logId);
    });
  }

  @override
  LastPerformance? lastPerformance(String exerciseName, {int? excludeLogId}) {
    final query = _entryBox
        .query(LogEntry_.exerciseNameSnapshot.equals(exerciseName))
        .build();
    try {
      // ObjectBox non ordina per proprietà dell'entità collegata: si filtra e
      // si ordina in memoria. Le occorrenze sono al più una per sessione.
      final candidates =
          query
              .find()
              .where((entry) => entry.sets.isNotEmpty)
              .map((entry) => (entry: entry, log: entry.log.target))
              .where(
                (row) =>
                    row.log != null &&
                    row.log!.status != WorkoutStatus.inProgress &&
                    row.log!.id != excludeLogId,
              )
              .toList()
            ..sort((a, b) => b.log!.startedAt.compareTo(a.log!.startedAt));

      if (candidates.isEmpty) return null;
      final best = candidates.first;
      final sets = best.entry.sets.toList()
        ..sort((a, b) => a.setNumber.compareTo(b.setNumber));
      return LastPerformance(performedAt: best.log!.startedAt, sets: sets);
    } finally {
      query.close();
    }
  }
}

/// Ordina in memoria entry e serie di [log], come `sortPlanTree` fa con le
/// schede: anche questa serve sia al repository sia al backup.
void sortLogTree(WorkoutLog log) {
  log.entries.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  for (final entry in log.entries) {
    entry.sets.sort((a, b) => a.setNumber.compareTo(b.setNumber));
  }
}

/// Esercizi prescritti di un giorno appiattiti nell'ordine di esecuzione
/// (blocchi in ordine, esercizi in ordine). I blocchi `freeText` non ne
/// producono.
///
/// È la sequenza che definisce il `sortOrder` delle entry del log: la stessa
/// funzione serve a crearle e a rimapparle quando una sessione viene ripresa.
List<Exercise> flattenExercises(WorkoutDay day) {
  return [for (final block in day.blocks) ...block.exercises];
}
