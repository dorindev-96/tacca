import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../data/entities/block.dart';
import '../../../data/entities/exercise.dart';
import '../../../data/entities/workout_day.dart';
import '../../../data/entities/workout_log.dart';
import '../../../data/repositories/workout_log_repository.dart';
import '../../../services/timer/timer_engine.dart';
import 'session_item.dart';
import 'session_step.dart';

part 'workout_session_state.freezed.dart';

enum WorkoutSessionStatus {
  /// Log e scheda in caricamento.
  loading,

  /// Sessione in corso.
  ready,

  /// Sessione chiusa: la pagina può uscire.
  finished,

  /// Log inesistente (link vecchio o sessione già eliminata).
  notFound,
}

/// Stato della sessione di allenamento (RF-06).
///
/// [log] e [day] sono entity ObjectBox mutate in place dal Bloc (ADR-01,
/// nessun domain layer separato): [revision] è il segnale esplicito che rende
/// visibile una mutazione interna all'uguaglianza generata da freezed, come
/// nell'editor delle schede.
@freezed
sealed class WorkoutSessionState with _$WorkoutSessionState {
  const WorkoutSessionState._();

  const factory WorkoutSessionState({
    @Default(WorkoutSessionStatus.loading) WorkoutSessionStatus status,

    /// Registro persistito della sessione.
    WorkoutLog? log,

    /// Struttura prescritta dalla scheda; nulla se la scheda non esiste più.
    WorkoutDay? day,

    @Default(0) int revision,

    /// Esercizio evidenziato nella vista palestra.
    @Default(0) int currentIndex,

    /// "Ultima volta" per nome esercizio, caricata all'apertura della sessione.
    @Default(<String, LastPerformance>{})
    Map<String, LastPerformance> lastPerformances,

    /// Timer attivo, `null` se nessuno.
    TimerState? timer,

    /// Timer richiesto mentre un altro è in corso: la UI chiede conferma
    /// prima di sostituirlo (analisi funzionale §9).
    TimerSpec? pendingTimerRequest,

    /// Avvio automatico del recupero dopo la spunta di una serie.
    @Default(true) bool autoStartRest,

    String? errorMessage,
  }) = _WorkoutSessionState;

  /// Righe della sessione: esercizi prescritti accostati alle entry del log.
  ///
  /// L'accoppiamento è posizionale perché il Bloc allinea le entry alla
  /// sequenza del giorno all'apertura; le entry eccedenti (esercizi non più
  /// in scheda ma già registrati) finiscono in coda senza prescrizione.
  List<SessionItem> get items {
    final currentLog = log;
    if (currentLog == null) return const [];

    final entries = currentLog.entries.toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    final planned = <(Block, Exercise)>[
      if (day case final WorkoutDay day)
        for (final block in day.blocks)
          for (final exercise in block.exercises) (block, exercise),
    ];

    return [
      for (var i = 0; i < entries.length; i++)
        SessionItem(
          index: i,
          entry: entries[i],
          block: i < planned.length ? planned[i].$1 : null,
          exercise: i < planned.length ? planned[i].$2 : null,
        ),
    ];
  }

  /// Blocchi del giorno nell'ordine di esecuzione (vuoto senza scheda).
  List<Block> get blocks => day?.blocks.toList() ?? const [];

  SessionItem? get currentItem {
    final all = items;
    if (all.isEmpty) return null;
    final index = currentIndex.clamp(0, all.length - 1);
    return all[index];
  }

  /// Il giro da chiudere col pulsante in fondo alla sessione: il primo ancora
  /// aperto nel superset o nel circuito dell'esercizio in evidenza. Null fuori
  /// da un gruppo a giri, o a gruppo finito.
  SessionStep? get currentRound {
    final item = currentItem;
    if (item == null) return null;
    final group = executionGroupOf(items, item.index);
    if (group.length < 2) return null;
    for (final step in pendingStepsOf(group)) {
      return step;
    }
    return null;
  }

  int get completedExercises => items.where((item) => item.isDone).length;

  int get loggedSets =>
      items.fold(0, (total, item) => total + item.entry.sets.length);

  bool get hasTimer => timer != null;
}
