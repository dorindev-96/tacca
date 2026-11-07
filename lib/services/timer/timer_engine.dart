import 'dart:async';
import 'dart:math' as math;

/// Tipo di timer, contestuale al tipo di blocco che lo ha richiesto (§7).
enum TimerKind {
  /// Countdown di recupero (standard, superset, circuito).
  rest,

  /// Intervalli fissi con segnale a ogni inizio round.
  emom,

  /// Countdown della durata complessiva.
  amrap,

  /// Alternanza lavoro/recupero per un numero fisso di round.
  tabata,

  /// Cronometro con time cap opzionale.
  forTime,
}

/// Fase corrente di un timer che alterna lavoro e recupero (tabata).
enum TimerPhase { work, rest }

/// Evento sonoro/vibrazione generato dal timer.
enum TimerSignal {
  /// Inizio di un nuovo round o cambio di fase (inizio minuto EMOM, passaggio
  /// lavoro↔recupero nel Tabata).
  interval,

  /// Il timer ha raggiunto la fine (recupero terminato, blocco concluso).
  finished,
}

/// Descrizione immutabile di un timer da avviare.
class TimerSpec {
  const TimerSpec({
    required this.kind,
    required this.total,
    this.interval,
    this.restInterval,
    this.rounds,
    this.label,
  });

  /// Countdown di recupero fra una serie e l'altra.
  factory TimerSpec.rest(Duration total, {String? label}) =>
      TimerSpec(kind: TimerKind.rest, total: total, label: label);

  /// EMOM: [interval] è la durata di ogni round, [total] la durata complessiva.
  factory TimerSpec.emom({
    required Duration interval,
    required Duration total,
    String? label,
  }) => TimerSpec(
    kind: TimerKind.emom,
    total: total,
    interval: interval,
    label: label,
  );

  factory TimerSpec.amrap(Duration total, {String? label}) =>
      TimerSpec(kind: TimerKind.amrap, total: total, label: label);

  /// Tabata: [interval] lavoro, [restInterval] recupero, per [rounds] round.
  factory TimerSpec.tabata({
    required Duration interval,
    required Duration restInterval,
    required int rounds,
    String? label,
  }) => TimerSpec(
    kind: TimerKind.tabata,
    total: (interval + restInterval) * rounds,
    interval: interval,
    restInterval: restInterval,
    rounds: rounds,
    label: label,
  );

  /// For Time: senza [timeCap] il timer conta in avanti senza fine.
  factory TimerSpec.forTime({Duration? timeCap, String? label}) => TimerSpec(
    kind: TimerKind.forTime,
    total: timeCap ?? Duration.zero,
    label: label,
  );

  final TimerKind kind;

  /// Durata complessiva o time cap. [Duration.zero] significa "cronometro
  /// senza fine" (solo `forTime` senza time cap).
  final Duration total;

  /// Durata del singolo round (emom) o della fase di lavoro (tabata).
  final Duration? interval;

  /// Durata della fase di recupero (solo tabata).
  final Duration? restInterval;

  /// Numero di round previsti (solo tabata; per l'EMOM si deriva da
  /// [total] / [interval]).
  final int? rounds;

  /// Etichetta mostrata in UI (nome del blocco o dell'esercizio).
  final String? label;

  /// Cronometro in avanti: nessuna fine, nessun countdown.
  bool get isCountUp => total <= Duration.zero;

  /// Round previsti complessivamente (1 quando il concetto non si applica).
  int get totalRounds {
    final step = interval;
    final count = switch (kind) {
      TimerKind.emom when step != null && step > Duration.zero =>
        total.inMilliseconds ~/ step.inMilliseconds,
      TimerKind.tabata => rounds ?? 1,
      TimerKind.emom ||
      TimerKind.rest ||
      TimerKind.amrap ||
      TimerKind.forTime => 1,
    };
    return math.max(count, 1);
  }
}

/// Fotografia del timer a un istante. Sempre **derivata** da `startedAt` e
/// dall'orologio di sistema: mai da un conteggio di tick (§7).
class TimerState {
  const TimerState({
    required this.spec,
    required this.startedAt,
    required this.elapsed,
    required this.round,
    required this.phase,
    required this.phaseRemaining,
    required this.isFinished,
  });

  final TimerSpec spec;
  final DateTime startedAt;
  final Duration elapsed;

  /// Round corrente, 1-based.
  final int round;

  /// Fase corrente: sempre [TimerPhase.work] fuori dal tabata.
  final TimerPhase phase;

  /// Tempo mancante alla fine della fase/round corrente. Per i timer senza
  /// round coincide con [remaining].
  final Duration phaseRemaining;

  final bool isFinished;

  int get totalRounds => spec.totalRounds;

  /// Tempo mancante alla fine, `null` per il cronometro senza time cap.
  Duration? get remaining =>
      spec.isCountUp ? null : _atLeastZero(spec.total - elapsed);

  /// Quota di avanzamento in [0, 1]; 0 per il cronometro senza time cap.
  double get progress {
    if (spec.isCountUp) return 0;
    final value = elapsed.inMilliseconds / spec.total.inMilliseconds;
    return value.clamp(0.0, 1.0);
  }
}

/// Motore dei timer della sessione (§7), indipendente dalla UI.
///
/// Decisioni chiave:
/// - lo stato è **sempre** ricalcolato da `startedAt + now()`, quindi resta
///   esatto dopo un periodo in background: il [Timer.periodic] serve solo a
///   emettere aggiornamenti per la UI;
/// - un solo timer alla volta: [start] sostituisce quello in corso. Il vincolo
///   "chiedi conferma prima di sostituire" (§9 funzionale) vive nel Bloc, che
///   interroga [isRunning];
/// - il motore non conosce audio, vibrazione né notifiche: espone [signals] e
///   [upcomingSignalTimes], e chi lo usa decide come renderli percepibili.
class TimerEngine {
  TimerEngine({
    DateTime Function()? now,
    Duration tickInterval = const Duration(milliseconds: 250),
  }) : _now = now ?? DateTime.now,
       _tickInterval = tickInterval;

  final DateTime Function() _now;
  final Duration _tickInterval;

  final _stateController = StreamController<TimerState>.broadcast();
  final _signalController = StreamController<TimerSignal>.broadcast();

  Timer? _ticker;
  TimerState? _current;

  /// Aggiornamenti di stato (circa 4 al secondo mentre un timer è attivo).
  Stream<TimerState> get stream => _stateController.stream;

  /// Eventi da rendere percepibili (beep, vibrazione, notifica).
  Stream<TimerSignal> get signals => _signalController.stream;

  TimerState? get current => _current;

  bool get isRunning => _current?.isFinished == false;

  /// Avvia [spec]. [startedAt] permette di riagganciarsi a un timer partito in
  /// passato (ripresa di una sessione): lo stato viene ricalcolato dall'inizio
  /// reale, non da adesso.
  void start(TimerSpec spec, {DateTime? startedAt}) {
    _ticker?.cancel();
    final state = _evaluate(spec, startedAt ?? _now());
    _current = state;
    _stateController.add(state);

    if (state.isFinished) {
      _signalController.add(TimerSignal.finished);
      return;
    }
    _ticker = Timer.periodic(_tickInterval, (_) => _tick());
  }

  /// Ferma il timer corrente senza emettere segnali.
  void stop() {
    _ticker?.cancel();
    _ticker = null;
    _current = null;
  }

  /// Ricalcola subito lo stato: da chiamare al rientro in foreground, dove i
  /// tick sono stati sospesi dal sistema ma il tempo è passato comunque.
  void reconcile() {
    if (_current == null) return;
    _tick();
  }

  /// Istanti futuri in cui il timer produrrà un segnale, in ordine cronologico.
  /// Servono a programmare le notifiche locali prima di andare in background
  /// (§7); [max] limita quante ne vengono richieste al sistema.
  List<DateTime> upcomingSignalTimes({int max = 10}) {
    final state = _current;
    if (state == null || state.isFinished || max <= 0) return const [];

    final spec = state.spec;
    final now = _now();
    final times = <DateTime>[];
    void addIfAhead(DateTime at) {
      if (at.isAfter(now)) times.add(at);
    }

    final step = spec.interval;
    if (spec.kind == TimerKind.tabata) {
      // Il tabata è a parte: alterna due fasi di durata diversa. Dopo
      // l'ultimo recupero non c'è un cambio di fase ma la fine, qui sotto.
      final work = spec.interval ?? Duration.zero;
      final rest = spec.restInterval ?? Duration.zero;
      var cursor = state.startedAt;
      for (var i = 0; i < spec.totalRounds; i++) {
        cursor = cursor.add(work);
        addIfAhead(cursor);
        cursor = cursor.add(rest);
        if (i < spec.totalRounds - 1) addIfAhead(cursor);
      }
    } else if (spec.kind == TimerKind.emom &&
        step != null &&
        step > Duration.zero) {
      for (var i = 1; i < spec.totalRounds; i++) {
        addIfAhead(state.startedAt.add(step * i));
      }
    }

    if (!spec.isCountUp) addIfAhead(state.startedAt.add(spec.total));

    times.sort();
    return times.take(max).toList();
  }

  Future<void> dispose() async {
    stop();
    await _stateController.close();
    await _signalController.close();
  }

  void _tick() {
    final previous = _current;
    if (previous == null) return;

    final next = _evaluate(previous.spec, previous.startedAt);
    _current = next;
    _stateController.add(next);

    // I segnali nascono dal confronto fra due stati, non dal conteggio dei
    // tick: al rientro dal background si emette una sola volta ciò che è
    // maturato nel frattempo, invece di una raffica di beep arretrati.
    if (next.isFinished) {
      _ticker?.cancel();
      _ticker = null;
      if (!previous.isFinished) _signalController.add(TimerSignal.finished);
      return;
    }
    if (next.round != previous.round || next.phase != previous.phase) {
      _signalController.add(TimerSignal.interval);
    }
  }

  TimerState _evaluate(TimerSpec spec, DateTime startedAt) {
    final elapsed = _atLeastZero(_now().difference(startedAt));
    final finished = !spec.isCountUp && elapsed >= spec.total;

    switch (spec.kind) {
      case TimerKind.emom:
        final step = spec.interval;
        if (step == null || step <= Duration.zero) {
          return _simpleState(spec, startedAt, elapsed, finished);
        }
        final index = elapsed.inMilliseconds ~/ step.inMilliseconds;
        final round = (index + 1).clamp(1, spec.totalRounds);
        final into = Duration(
          milliseconds: elapsed.inMilliseconds % step.inMilliseconds,
        );
        return TimerState(
          spec: spec,
          startedAt: startedAt,
          elapsed: elapsed,
          round: finished ? spec.totalRounds : round,
          phase: TimerPhase.work,
          phaseRemaining: finished ? Duration.zero : step - into,
          isFinished: finished,
        );

      case TimerKind.tabata:
        final work = spec.interval ?? Duration.zero;
        final rest = spec.restInterval ?? Duration.zero;
        final cycle = work + rest;
        if (cycle <= Duration.zero) {
          return _simpleState(spec, startedAt, elapsed, finished);
        }
        final index = elapsed.inMilliseconds ~/ cycle.inMilliseconds;
        final into = Duration(
          milliseconds: elapsed.inMilliseconds % cycle.inMilliseconds,
        );
        final isWork = into < work;
        return TimerState(
          spec: spec,
          startedAt: startedAt,
          elapsed: elapsed,
          round: finished
              ? spec.totalRounds
              : (index + 1).clamp(1, spec.totalRounds),
          phase: isWork ? TimerPhase.work : TimerPhase.rest,
          phaseRemaining: finished
              ? Duration.zero
              : (isWork ? work - into : cycle - into),
          isFinished: finished,
        );

      case TimerKind.rest:
      case TimerKind.amrap:
      case TimerKind.forTime:
        return _simpleState(spec, startedAt, elapsed, finished);
    }
  }

  TimerState _simpleState(
    TimerSpec spec,
    DateTime startedAt,
    Duration elapsed,
    bool finished,
  ) {
    return TimerState(
      spec: spec,
      startedAt: startedAt,
      elapsed: elapsed,
      round: 1,
      phase: TimerPhase.work,
      phaseRemaining: spec.isCountUp
          ? Duration.zero
          : _atLeastZero(spec.total - elapsed),
      isFinished: finished,
    );
  }
}

/// Una durata calcolata dall'orologio non va mai sotto lo zero: né il tempo
/// trascorso di un timer che parte nel futuro, né quello che manca a uno già
/// finito.
Duration _atLeastZero(Duration value) =>
    value.isNegative ? Duration.zero : value;
