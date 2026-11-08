import '../../../data/entities/block.dart';
import '../../../data/entities/exercise.dart';
import '../../../data/entities/log_entry.dart';
import '../../../data/entities/log_set.dart';
import '../../../data/repositories/workout_log_repository.dart';

/// Una riga della sessione: l'esercizio **prescritto** dalla scheda accostato
/// al **registro** delle serie effettivamente svolte.
///
/// [block] ed [exercise] sono nulli quando la struttura originale non è più
/// disponibile (scheda modificata o eliminata mentre la sessione era aperta):
/// in quel caso restano lo snapshot del nome e le serie già registrate, che
/// non vanno mai persi (analisi funzionale §9).
class SessionItem {
  const SessionItem({
    required this.index,
    required this.entry,
    this.block,
    this.exercise,
  });

  /// Posizione nella sequenza del giorno, coincide con `LogEntry.sortOrder`.
  final int index;

  final LogEntry entry;
  final Block? block;
  final Exercise? exercise;

  String get name => exercise?.name ?? entry.exerciseNameSnapshot;

  /// Superset e circuito si eseguono **a giri**: il numero di ripetizioni del
  /// gruppo sta sul blocco (`rounds`), non sulle serie del singolo esercizio.
  /// In sessione un giro vale una serie di ciascun esercizio del gruppo.
  bool get isRoundBased =>
      block?.type == BlockType.superset || block?.type == BlockType.circuit;

  /// Giri prescritti dal blocco, `null` se il blocco non li specifica o non è
  /// un blocco a giri.
  int? get blockRounds {
    if (!isRoundBased) return null;
    final rounds = block?.rounds;
    return (rounds != null && rounds > 0) ? rounds : null;
  }

  /// Serie previste dalla scheda; 0 se non specificate. Nei blocchi a giri
  /// valgono i giri del blocco, salvo che l'esercizio prescriva le sue serie.
  int get plannedSets => exercise?.sets ?? blockRounds ?? 0;

  /// Ultimo esercizio del suo blocco: è lì che finisce il giro, quindi è lì
  /// che nasce il recupero fra i giri di superset e circuiti.
  bool get isLastOfBlock {
    final parent = block;
    final current = exercise;
    if (parent == null || current == null) return true;
    final siblings = parent.exercises;
    if (siblings.isEmpty) return true;
    var last = siblings.first;
    for (final sibling in siblings) {
      if (sibling.sortOrder >= last.sortOrder) last = sibling;
    }
    return identical(last, current);
  }

  /// Numero di serie da mostrare: quelle previste, ma mai meno di quelle già
  /// registrate (l'utente può averne fatta una in più).
  int get displayedSets {
    var shown = plannedSets;
    for (final set in entry.sets) {
      if (set.setNumber > shown) shown = set.setNumber;
    }
    return shown;
  }

  /// Serie che si possono spuntare: [displayedSets], ma mai meno di una.
  ///
  /// Un esercizio senza serie prescritte — un riscaldamento a tempo, una
  /// corsa — ne ha comunque una da confermare, ed è la riga che la card
  /// disegna. La regola sta qui e non nella card perché la stessa serie deve
  /// esistere anche per la schermata di blocco: quando la contava solo la
  /// card, quell'esercizio sulla superficie di sistema non compariva affatto
  /// e il banner saltava direttamente a quello dopo.
  int get checkableSets => displayedSets > 0 ? displayedSets : 1;

  /// Serie registrate, ordinate per numero.
  List<LogSet> get completedSets =>
      entry.sets.toList()..sort((a, b) => a.setNumber.compareTo(b.setNumber));

  LogSet? setNumbered(int setNumber) =>
      entry.sets.where((set) => set.setNumber == setNumber).firstOrNull;

  bool isSetDone(int setNumber) => setNumbered(setNumber) != null;

  /// L'esercizio è considerato svolto quando ha almeno una serie registrata e
  /// non ne mancano rispetto a quelle previste.
  bool get isDone {
    if (entry.sets.isEmpty) return false;
    return entry.sets.length >= displayedSets;
  }
}

/// L'avanzamento di una sessione, contato sulle sue righe.
extension SessionProgress on Iterable<SessionItem> {
  /// Esercizi svolti ([SessionItem.isDone]).
  int get completedCount => where((item) => item.isDone).length;

  /// Serie registrate in tutto.
  int get loggedSetCount =>
      fold(0, (total, item) => total + item.entry.sets.length);
}

/// I valori con cui parte la serie [setNumber] di [item]: li registra la
/// spunta e li propone il log rapido, che devono dire la stessa cosa.
///
/// Minimo attrito (RF-06): il riferimento è l'ultima serie già fatta *in
/// questa sessione* prima di [setNumber], poi l'ultima di [lastTime] (la volta
/// scorsa). Il peso viene solo dal riferimento — il carico prescritto è testo
/// libero ("70% 1RM"), non un numero di kg. Le ripetizioni vengono dal
/// riferimento e, se lì mancano, dalla prescrizione: una serie registrata
/// senza ripetizioni non dice "zero", dice "non annotate", e la scheda è
/// l'ipotesi migliore.
({double? weightKg, String? reps}) setPrefill(
  SessionItem item,
  int setNumber, {
  LastPerformance? lastTime,
}) {
  final reference =
      item.completedSets.where((s) => s.setNumber < setNumber).lastOrNull ??
      lastTime?.sets.lastOrNull;
  final reps = reference?.reps?.trim();
  return (
    weightKg: reference?.weightKg,
    reps: reps == null || reps.isEmpty ? item.exercise?.reps : reps,
  );
}
