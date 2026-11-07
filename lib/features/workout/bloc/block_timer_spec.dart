import '../../../data/entities/block.dart';
import '../../../services/timer/timer_engine.dart';
import 'session_item.dart';
import 'session_step.dart';

/// Timer "di blocco": quello che guida l'esecuzione dell'intero blocco
/// (EMOM, AMRAP, Tabata, For Time). I blocchi a serie classiche non ne hanno
/// uno: lì il timer nasce dalla spunta di una serie ([restTimerSpec]).
TimerSpec? blockTimerSpec(Block block, {String? label}) {
  switch (block.type) {
    case BlockType.emom:
      final interval = block.intervalSeconds;
      final minutes = block.totalMinutes;
      if (interval == null ||
          interval <= 0 ||
          minutes == null ||
          minutes <= 0) {
        return null;
      }
      return TimerSpec.emom(
        interval: Duration(seconds: interval),
        total: Duration(minutes: minutes),
        label: label,
      );

    case BlockType.amrap:
      final seconds = block.durationSeconds;
      if (seconds == null || seconds <= 0) return null;
      return TimerSpec.amrap(Duration(seconds: seconds), label: label);

    case BlockType.tabata:
      final work = block.workSeconds;
      final rest = block.restSeconds;
      final rounds = block.rounds;
      if (work == null || work <= 0 || rounds == null || rounds <= 0) {
        return null;
      }
      return TimerSpec.tabata(
        interval: Duration(seconds: work),
        restInterval: Duration(seconds: rest ?? 0),
        rounds: rounds,
        label: label,
      );

    case BlockType.forTime:
      final cap = block.timeCapSeconds;
      return TimerSpec.forTime(
        timeCap: (cap != null && cap > 0) ? Duration(seconds: cap) : null,
        label: label,
      );

    case BlockType.standard:
    case BlockType.superset:
    case BlockType.circuit:
    case BlockType.freeText:
      return null;
  }
}

/// Recupero da avviare dopo la spunta di una serie.
///
/// Prevale il recupero dell'esercizio. Nei blocchi a giri (superset, circuito)
/// il recupero è del *giro*: nasce solo dall'ultimo esercizio del gruppo —
/// fermarsi fra un esercizio e l'altro sarebbe l'esatto contrario di un
/// superset. Nessun valore configurato significa nessun timer automatico: non
/// si inventa una durata.
TimerSpec? restTimerSpec(SessionItem item) =>
    _rest(item.exercise?.restSeconds, item.name) ??
    (item.isRoundBased && item.isLastOfBlock
        ? _rest(item.block?.restBetweenRoundsSeconds, item.name)
        : null);

/// Recupero da avviare a giro concluso (superset, circuito): quello che
/// partirebbe spuntando [closing], l'esercizio che chiude il giro.
///
/// Si scosta da [restTimerSpec] in un caso solo: quando a chiudere il giro non
/// è l'ultimo esercizio del blocco — uno che prescrive più serie degli altri e
/// gli ultimi giri li fa da solo. Il giro è finito lo stesso, e il recupero
/// fra i giri gli spetta.
TimerSpec? roundRestSpec(SessionItem closing, {required String label}) =>
    _rest(closing.exercise?.restSeconds, label) ??
    _rest(closing.block?.restBetweenRoundsSeconds, label);

/// Un recupero di [seconds], se ne è configurato uno.
TimerSpec? _rest(int? seconds, String label) => seconds != null && seconds > 0
    ? TimerSpec.rest(Duration(seconds: seconds), label: label)
    : null;

/// Recupero da avviare confermando [step]: quello del giro se il passo è un
/// giro intero, quello della serie altrimenti.
TimerSpec? stepRestSpec(SessionStep step) => step.isRound
    ? roundRestSpec(step.closing, label: step.title)
    : restTimerSpec(step.anchor);
