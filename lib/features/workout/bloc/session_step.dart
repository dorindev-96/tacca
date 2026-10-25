import 'session_item.dart';

/// Esercizi che si eseguono insieme, un giro alla volta: quelli consecutivi di
/// uno stesso superset o circuito. Ogni altro esercizio è un gruppo di uno.
///
/// Gli esercizi di un gruppo sono sempre consecutivi: `items` li costruisce
/// seguendo i blocchi del giorno.
List<List<SessionItem>> executionGroups(List<SessionItem> items) {
  final groups = <List<SessionItem>>[];
  var i = 0;
  while (i < items.length) {
    final group = <SessionItem>[items[i]];
    final block = items[i].block;
    if (items[i].isRoundBased && block != null) {
      while (i + 1 < items.length && identical(items[i + 1].block, block)) {
        group.add(items[i + 1]);
        i++;
      }
    }
    groups.add(group);
    i++;
  }
  return groups;
}

/// Il gruppo di cui fa parte l'esercizio in posizione [index].
List<SessionItem> executionGroupOf(List<SessionItem> items, int index) {
  for (final group in executionGroups(items)) {
    if (group.any((item) => item.index == index)) return group;
  }
  return const [];
}

/// Ciò che si conferma con un tocco solo: una serie di un esercizio o, in un
/// superset e in un circuito, il **giro intero**.
///
/// Un giro è una serie di ciascun esercizio del gruppo, e durante il giro non
/// ci si ferma: il telefono si riprende in mano alla fine, ed è lì che le
/// spunte vanno date tutte insieme, recupero compreso. Contarle una per una
/// voleva dire tre tocchi (A, B, poi il recupero che partiva dal secondo) per
/// dire una cosa sola.
class SessionStep {
  const SessionStep({required this.group, required this.number});

  /// Il gruppo del passo: un esercizio solo per una serie, tutti quelli del
  /// superset o del circuito per un giro.
  final List<SessionItem> group;

  /// Numero della serie, o del giro.
  final int number;

  /// Un giro intero: più esercizi spuntati insieme. Un superset di un
  /// esercizio solo non lo è — lì giro e serie coincidono.
  bool get isRound => group.length > 1;

  /// Primo esercizio del gruppo: è lui a identificare il passo nelle azioni
  /// che arrivano dalla schermata di blocco.
  SessionItem get anchor => group.first;

  /// Esercizi che fanno questo giro. Un esercizio del gruppo può prescrivere
  /// serie sue: i giri sono tanti quanti ne chiede il più lungo, e chi ne ha
  /// meno esce prima.
  List<SessionItem> get participants => [
    // `checkableSets`, non `displayedSets`: un esercizio senza serie
    // prescritte ne ha comunque una da spuntare.
    for (final item in group)
      if (number <= item.checkableSets) item,
  ];

  /// Esercizi del passo ancora da spuntare. Un giro cominciato a mano — il
  /// primo esercizio già spuntato — si chiude spuntando il resto.
  List<SessionItem> get pending => [
    for (final item in participants)
      if (!item.isSetDone(number)) item,
  ];

  /// L'esercizio che chiude il giro: è da lui che nasce il recupero.
  SessionItem get closing {
    final all = participants;
    return all.isEmpty ? group.last : all.last;
  }

  /// Serie dell'esercizio, o giri del gruppo; 0 se la scheda non li
  /// prescrive (si scrive "Serie 1" senza denominatore).
  int get total {
    var total = 0;
    for (final item in group) {
      if (item.displayedSets > total) total = item.displayedSets;
    }
    return total;
  }

  /// Nome del passo: l'esercizio, o quelli del giro uniti da "+" — la stessa
  /// notazione con cui un superset si scrive su una scheda di carta.
  String get title => participants.map((item) => item.name).join(' + ');

  /// Ultima posizione occupata dal gruppo: un passo "comincia" dall'esercizio
  /// in evidenza anche se quello è il secondo del superset.
  int get lastIndex => group.last.index;
}

/// I passi ancora aperti di un gruppo, giro dopo giro.
Iterable<SessionStep> pendingStepsOf(List<SessionItem> group) sync* {
  var rounds = 0;
  for (final item in group) {
    if (item.checkableSets > rounds) rounds = item.checkableSets;
  }
  for (var number = 1; number <= rounds; number++) {
    final step = SessionStep(group: group, number: number);
    if (step.pending.isNotEmpty) yield step;
  }
}

/// Tutti i passi rimasti, nell'ordine in cui si eseguono davvero: le serie
/// di un esercizio una dopo l'altra, i giri di un superset uno dopo l'altro.
List<SessionStep> pendingSteps(List<SessionItem> items) => [
  for (final group in executionGroups(items)) ...pendingStepsOf(group),
];

/// I passi rimasti a partire dall'esercizio in posizione [start].
///
/// La sequenza viene **ruotata**, non tagliata: i passi prima di [start] non
/// si perdono, si raccolgono in fondo. È il modo in cui una serie saltata
/// torna comunque sotto il pulsante, una volta finito il resto.
List<SessionStep> pendingStepsFrom(List<SessionItem> items, int start) {
  final steps = pendingSteps(items);
  final from = steps.indexWhere((step) => step.lastIndex >= start);
  if (from <= 0) return steps;
  return [...steps.skip(from), ...steps.take(from)];
}
