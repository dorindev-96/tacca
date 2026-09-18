import 'dart:async';

/// Superficie di sistema che mostra la sessione fuori dall'app e accetta la
/// conferma di una serie a telefono bloccato (RF-06).
///
/// Le due piattaforme la realizzano in modo diverso — Live Activity di
/// ActivityKit su iOS, notifica persistente su Android — ma il contratto è lo
/// stesso: si pubblica uno [LiveSessionSnapshot] e si raccolgono le
/// [LiveSessionAction] che l'utente ha eseguito da lì.
///
/// **Il tap non passa dal motore Dart.** Su iOS l'App Intent gira ad app
/// sospesa, su Android il broadcast può arrivare a processo ucciso: in
/// entrambi i casi l'azione viene messa in una coda durabile e l'app la drena
/// al rientro ([drainPendingActions]). [actions] serve solo alla consegna
/// immediata quando l'app è ancora viva; l'id dell'azione permette di
/// riconoscere il doppione fra le due strade.
abstract interface class LiveSessionController {
  /// Azioni consegnate mentre l'app è in esecuzione.
  Stream<LiveSessionAction> get actions;

  /// `false` dove la superficie non esiste (iOS < 16.2, Live Activity
  /// disattivate dall'utente, piattaforme desktop): la sessione funziona
  /// comunque, semplicemente senza banner.
  Future<bool> isSupported();

  /// Mostra la superficie. Su iOS va chiamata con l'app in primo piano:
  /// ActivityKit non permette di avviare un'attività dal background.
  Future<void> start(LiveSessionSnapshot snapshot);

  /// Aggiorna la superficie già avviata. Non va chiamata a ogni tick del
  /// timer: il countdown lo disegna il sistema a partire da
  /// [LiveSessionSnapshot.countdownEndsAt].
  Future<void> update(LiveSessionSnapshot snapshot);

  /// Rimuove la superficie (fine o abbandono della sessione).
  Future<void> stop();

  /// Restituisce e svuota le azioni accumulate mentre l'app non era attiva.
  Future<List<LiveSessionAction>> drainPendingActions();

  Future<void> dispose();
}

/// Stato pubblicato sulla superficie di sistema.
///
/// Contiene tutto quello che serve al nativo per disegnare il banner **e** per
/// reagire da solo al tap: [restSecondsOnComplete] gli permette di far partire
/// il countdown, i campi `next*` di spostare il banco sull'esercizio dopo —
/// entrambi senza aspettare che l'app si risvegli.
class LiveSessionSnapshot {
  const LiveSessionSnapshot({
    required this.logId,
    required this.exerciseName,
    required this.entryIndex,
    required this.setNumber,
    required this.totalSets,
    required this.canCompleteSet,
    required this.advancesToNext,
    required this.restSecondsOnComplete,
    required this.labels,
    this.countdownStartsAt,
    this.countdownEndsAt,
    this.countdownLabel,
    this.nextExerciseName,
    this.nextEntryIndex = 0,
    this.nextSetNumber = 0,
    this.nextTotalSets = 0,
    this.nextRestSecondsOnComplete = 0,
    this.nextAdvancesToNext = false,
  });

  /// Sessione a cui appartiene: un'azione rimasta in coda da un allenamento
  /// precedente viene scartata invece di finire nel log sbagliato.
  final int logId;

  final String exerciseName;

  /// Posizione dell'esercizio nella sequenza del giorno (`LogEntry.sortOrder`).
  final int entryIndex;

  /// Prossima serie da confermare.
  final int setNumber;

  /// Serie previste per l'esercizio; 0 se la scheda non le specifica.
  final int totalSets;

  /// `false` quando non c'è più niente da spuntare: il nativo nasconde il
  /// pulsante invece di registrare una serie che non esiste.
  final bool canCompleteSet;

  /// `true` quando la serie dopo questa è di un **altro** esercizio: il
  /// nativo deve saltare a `next*` invece di contare avanti qui.
  ///
  /// È il caso dei blocchi a giri. In un superset un giro è una serie di
  /// ciascun esercizio del gruppo, quindi dopo "Curl, giro 1" viene
  /// "Pushdown, giro 1", non "Curl, giro 2" — contare avanti registrerebbe
  /// giri che l'utente non ha fatto e l'altro esercizio non arriverebbe mai
  /// sul banner. Non si ricava da un tipo di blocco: lo decide l'app
  /// guardando qual è davvero la prossima serie rimasta, così un gruppo a
  /// giri di un esercizio solo continua a contare avanti come deve.
  final bool advancesToNext;

  /// Recupero da avviare alla conferma, in secondi. 0 significa nessun
  /// countdown (recupero non configurato o avvio automatico disattivato).
  final int restSecondsOnComplete;

  /// Inizio del countdown in corso: serve al nativo per disegnare la barra di
  /// avanzamento, non solo il tempo che manca.
  final DateTime? countdownStartsAt;

  /// Fine del countdown in corso, se ce n'è uno.
  final DateTime? countdownEndsAt;

  /// Etichetta del countdown in corso ("Recupero", o il nome del blocco per i
  /// timer EMOM/AMRAP/Tabata).
  final String? countdownLabel;

  /// Esercizio su cui si sposta il banner quando le serie di questo finiscono,
  /// `null` se non ne resta nessuno.
  ///
  /// È l'unico passo avanti che il nativo può fare da solo: senza, alla
  /// conferma dell'ultima serie mostrerebbe una serie che non esiste ("4/3").
  /// Il passo successivo lo ricalcola l'app al risveglio.
  final String? nextExerciseName;

  /// Coordinate della prima serie da spuntare di [nextExerciseName]: viaggiano
  /// nell'azione messa in coda, quindi devono essere quelle vere e non un
  /// "serie 1" dato per scontato.
  final int nextEntryIndex;
  final int nextSetNumber;
  final int nextTotalSets;

  /// Recupero da avviare confermando una serie di [nextExerciseName].
  final int nextRestSecondsOnComplete;

  /// [advancesToNext] di [nextExerciseName]: viaggia con gli altri `next*`
  /// perché senza, arrivato lì, il nativo non saprebbe se può continuare a
  /// contare da solo (blocco normale) o se deve fermarsi (blocco a giri).
  final bool nextAdvancesToNext;

  final LiveSessionLabels labels;

  Map<String, Object?> toMap() => {
    'logId': logId,
    'exerciseName': exerciseName,
    'entryIndex': entryIndex,
    'setNumber': setNumber,
    'totalSets': totalSets,
    'canCompleteSet': canCompleteSet,
    'advancesToNext': advancesToNext,
    'restSecondsOnComplete': restSecondsOnComplete,
    'countdownStartsAt': countdownStartsAt?.millisecondsSinceEpoch,
    'countdownEndsAt': countdownEndsAt?.millisecondsSinceEpoch,
    'countdownLabel': countdownLabel,
    'nextExerciseName': nextExerciseName,
    'nextEntryIndex': nextEntryIndex,
    'nextSetNumber': nextSetNumber,
    'nextTotalSets': nextTotalSets,
    'nextRestSecondsOnComplete': nextRestSecondsOnComplete,
    'nextAdvancesToNext': nextAdvancesToNext,
    ...labels.toMap(),
  };

  /// Ricostruisce uno snapshot da [toMap]: lo rilegge l'isolate di background
  /// di Android, che riceve lo stato della notifica dentro il payload e non ha
  /// nessun altro modo di sapere cosa c'era scritto.
  static LiveSessionSnapshot? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final labels = LiveSessionLabels.tryParse(raw);
    final logId = raw['logId'];
    final exerciseName = raw['exerciseName'];
    final entryIndex = raw['entryIndex'];
    final setNumber = raw['setNumber'];
    final totalSets = raw['totalSets'];
    final canCompleteSet = raw['canCompleteSet'];
    final restSecondsOnComplete = raw['restSecondsOnComplete'];
    if (labels == null ||
        logId is! int ||
        exerciseName is! String ||
        entryIndex is! int ||
        setNumber is! int ||
        totalSets is! int ||
        canCompleteSet is! bool ||
        restSecondsOnComplete is! int) {
      return null;
    }
    return LiveSessionSnapshot(
      logId: logId,
      exerciseName: exerciseName,
      entryIndex: entryIndex,
      setNumber: setNumber,
      totalSets: totalSets,
      canCompleteSet: canCompleteSet,
      // Un campo assente vale "come prima": la coda può portare il payload
      // scritto da una versione dell'app che non lo mandava ancora.
      advancesToNext: raw['advancesToNext'] as bool? ?? false,
      restSecondsOnComplete: restSecondsOnComplete,
      countdownStartsAt: _dateOrNull(raw['countdownStartsAt']),
      countdownEndsAt: _dateOrNull(raw['countdownEndsAt']),
      countdownLabel: raw['countdownLabel'] as String?,
      nextExerciseName: raw['nextExerciseName'] as String?,
      nextEntryIndex: raw['nextEntryIndex'] as int? ?? 0,
      nextSetNumber: raw['nextSetNumber'] as int? ?? 0,
      nextTotalSets: raw['nextTotalSets'] as int? ?? 0,
      nextRestSecondsOnComplete: raw['nextRestSecondsOnComplete'] as int? ?? 0,
      nextAdvancesToNext: raw['nextAdvancesToNext'] as bool? ?? false,
      labels: labels,
    );
  }

  /// Lo stato in cui la superficie si trova subito dopo una conferma, con il
  /// recupero avviato all'orario del tap.
  ///
  /// È l'unico passo avanti che si può fare senza l'app, e la stessa
  /// aritmetica sta in `CompleteSetIntent.swift`: le due copie devono restare
  /// identiche — questa ha dei test, quella no.
  LiveSessionSnapshot afterSetCompleted(DateTime at) {
    final endsAt = restSecondsOnComplete > 0
        ? at.add(Duration(seconds: restSecondsOnComplete))
        : null;

    // Su cosa si sposta il banner. Tre casi, gli stessi dell'App Intent.
    final focus = switch (this) {
      // Restano serie di questo esercizio: si conta avanti e basta. Non in un
      // blocco a giri, dove la serie dopo è di un altro esercizio: lì
      // [advancesToNext] manda direttamente al caso sotto.
      _ when !advancesToNext && totalSets > 0 && setNumber < totalSets => (
        exerciseName: exerciseName,
        entryIndex: entryIndex,
        setNumber: setNumber + 1,
        totalSets: totalSets,
        restSecondsOnComplete: restSecondsOnComplete,
        canCompleteSet: true,
        advancesToNext: advancesToNext,
        keepLookahead: true,
      ),
      // Erano finite: si passa all'esercizio dopo, quello che l'app ha
      // mandato insieme a questo. Un passo solo — quale sia quello ancora
      // dopo lo sa soltanto lei, e il campo si azzera.
      _ when nextExerciseName != null => (
        exerciseName: nextExerciseName!,
        entryIndex: nextEntryIndex,
        setNumber: nextSetNumber,
        totalSets: nextTotalSets,
        restSecondsOnComplete: nextRestSecondsOnComplete,
        canCompleteSet: nextSetNumber > 0,
        // Arrivati lì, se anche quello è un esercizio a giri il passo
        // successivo non si può fare da soli: senza lookahead il pulsante
        // sparisce, che è meglio di registrare un giro mai fatto.
        advancesToNext: nextAdvancesToNext,
        keepLookahead: false,
      ),
      // Niente più da spuntare: il contatore resta sull'ultima serie fatta e
      // il pulsante sparisce. Non si inventa una serie in più.
      _ => (
        exerciseName: exerciseName,
        entryIndex: entryIndex,
        setNumber: setNumber,
        totalSets: totalSets,
        restSecondsOnComplete: restSecondsOnComplete,
        canCompleteSet: false,
        advancesToNext: advancesToNext,
        keepLookahead: true,
      ),
    };

    return LiveSessionSnapshot(
      logId: logId,
      exerciseName: focus.exerciseName,
      entryIndex: focus.entryIndex,
      setNumber: focus.setNumber,
      totalSets: focus.totalSets,
      canCompleteSet: focus.canCompleteSet,
      advancesToNext: focus.advancesToNext,
      restSecondsOnComplete: focus.restSecondsOnComplete,
      countdownStartsAt: endsAt == null ? null : at,
      countdownEndsAt: endsAt,
      countdownLabel: endsAt == null ? null : labels.restLabel,
      nextExerciseName: focus.keepLookahead ? nextExerciseName : null,
      nextEntryIndex: focus.keepLookahead ? nextEntryIndex : 0,
      nextSetNumber: focus.keepLookahead ? nextSetNumber : 0,
      nextTotalSets: focus.keepLookahead ? nextTotalSets : 0,
      nextRestSecondsOnComplete: focus.keepLookahead
          ? nextRestSecondsOnComplete
          : 0,
      nextAdvancesToNext: focus.keepLookahead ? nextAdvancesToNext : false,
      labels: labels,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LiveSessionSnapshot &&
      other.logId == logId &&
      other.exerciseName == exerciseName &&
      other.entryIndex == entryIndex &&
      other.setNumber == setNumber &&
      other.totalSets == totalSets &&
      other.canCompleteSet == canCompleteSet &&
      other.advancesToNext == advancesToNext &&
      other.restSecondsOnComplete == restSecondsOnComplete &&
      other.countdownStartsAt == countdownStartsAt &&
      other.countdownEndsAt == countdownEndsAt &&
      other.countdownLabel == countdownLabel &&
      other.nextExerciseName == nextExerciseName &&
      other.nextEntryIndex == nextEntryIndex &&
      other.nextSetNumber == nextSetNumber &&
      other.nextTotalSets == nextTotalSets &&
      other.nextRestSecondsOnComplete == nextRestSecondsOnComplete &&
      other.nextAdvancesToNext == nextAdvancesToNext &&
      other.labels == labels;

  @override
  int get hashCode => Object.hash(
    logId,
    exerciseName,
    entryIndex,
    setNumber,
    totalSets,
    canCompleteSet,
    advancesToNext,
    restSecondsOnComplete,
    countdownStartsAt,
    countdownEndsAt,
    countdownLabel,
    nextExerciseName,
    nextEntryIndex,
    nextSetNumber,
    nextTotalSets,
    nextRestSecondsOnComplete,
    nextAdvancesToNext,
    labels,
  );
}

/// Stringhe localizzate che viaggiano insieme allo stato.
///
/// Il codice nativo non può leggere gli ARB e il pulsante deve restare in
/// italiano anche quando lo disegna SwiftUI: le etichette si passano, non si
/// scrivono di là.
class LiveSessionLabels {
  const LiveSessionLabels({
    required this.title,
    required this.setsLabel,
    required this.completeAction,
    required this.restLabel,
    required this.restDoneLabel,
  });

  /// Nome della superficie ("Allenamento").
  final String title;

  /// Parola per le serie: il nativo ci accosta "2/4".
  final String setsLabel;

  /// Etichetta del pulsante ("Serie fatta").
  final String completeAction;

  /// Etichetta del countdown di recupero.
  final String restLabel;

  /// Testo mostrato quando il countdown è finito.
  final String restDoneLabel;

  Map<String, Object?> toMap() => {
    'title': title,
    'setsLabel': setsLabel,
    'completeAction': completeAction,
    'restLabel': restLabel,
    'restDoneLabel': restDoneLabel,
  };

  /// Rilegge le etichette dalla mappa piatta prodotta da
  /// [LiveSessionSnapshot.toMap]; `null` se ne manca anche una sola: senza
  /// non si disegna niente di leggibile.
  static LiveSessionLabels? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final title = raw['title'];
    final setsLabel = raw['setsLabel'];
    final completeAction = raw['completeAction'];
    final restLabel = raw['restLabel'];
    final restDoneLabel = raw['restDoneLabel'];
    if (title is! String ||
        setsLabel is! String ||
        completeAction is! String ||
        restLabel is! String ||
        restDoneLabel is! String) {
      return null;
    }
    return LiveSessionLabels(
      title: title,
      setsLabel: setsLabel,
      completeAction: completeAction,
      restLabel: restLabel,
      restDoneLabel: restDoneLabel,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LiveSessionLabels &&
      other.title == title &&
      other.setsLabel == setsLabel &&
      other.completeAction == completeAction &&
      other.restLabel == restLabel &&
      other.restDoneLabel == restDoneLabel;

  @override
  int get hashCode =>
      Object.hash(title, setsLabel, completeAction, restLabel, restDoneLabel);
}

/// Cosa ha premuto l'utente sulla superficie di sistema.
enum LiveSessionActionKind {
  /// Conferma della serie corrente: registra la serie e avvia il recupero.
  setCompleted;

  static LiveSessionActionKind? parse(String? name) {
    for (final kind in values) {
      if (kind.name == name) return kind;
    }
    return null;
  }
}

/// Azione eseguita fuori dall'app.
///
/// [at] è il momento del tap, non quello della consegna: il recupero deve
/// partire da quando l'utente ha finito la serie, anche se l'app riapre gli
/// occhi cinque minuti dopo.
class LiveSessionAction {
  const LiveSessionAction({
    required this.id,
    required this.kind,
    required this.logId,
    required this.entryIndex,
    required this.setNumber,
    required this.at,
  });

  /// Identificatore univoco generato dal nativo: la stessa azione può
  /// arrivare sia da [LiveSessionController.actions] sia dal drain.
  final String id;

  final LiveSessionActionKind kind;
  final int logId;
  final int entryIndex;
  final int setNumber;
  final DateTime at;

  /// Decodifica una voce della coda nativa; `null` se il payload non è
  /// utilizzabile (versione vecchia della coda, campo mancante).
  static LiveSessionAction? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final kind = LiveSessionActionKind.parse(raw['kind'] as String?);
    final id = raw['id'];
    final at = raw['at'];
    if (kind == null || id is! String || at is! int) return null;
    final logId = raw['logId'];
    final entryIndex = raw['entryIndex'];
    final setNumber = raw['setNumber'];
    if (logId is! int || entryIndex is! int || setNumber is! int) return null;
    return LiveSessionAction(
      id: id,
      kind: kind,
      logId: logId,
      entryIndex: entryIndex,
      setNumber: setNumber,
      at: DateTime.fromMillisecondsSinceEpoch(at),
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'kind': kind.name,
    'logId': logId,
    'entryIndex': entryIndex,
    'setNumber': setNumber,
    'at': at.millisecondsSinceEpoch,
  };
}

/// Nessuna superficie di sistema: piattaforme senza supporto e test.
class NoopLiveSessionController implements LiveSessionController {
  const NoopLiveSessionController();

  @override
  Stream<LiveSessionAction> get actions => const Stream.empty();

  @override
  Future<bool> isSupported() async => false;

  @override
  Future<void> start(LiveSessionSnapshot snapshot) async {}

  @override
  Future<void> update(LiveSessionSnapshot snapshot) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<List<LiveSessionAction>> drainPendingActions() async => const [];

  @override
  Future<void> dispose() async {}
}

/// Millisecondi dall'epoch → data, tollerante: un campo assente o di tipo
/// sbagliato vale "nessun countdown", non un errore.
DateTime? _dateOrNull(Object? raw) =>
    raw is int ? DateTime.fromMillisecondsSinceEpoch(raw) : null;
