import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/entities/log_entry.dart';
import '../../../data/entities/log_set.dart';
import '../../../data/entities/workout_day.dart';
import '../../../data/entities/workout_log.dart';
import '../../../data/repositories/plan_repository.dart';
import '../../../data/repositories/workout_log_repository.dart';
import '../../../services/feedback/session_feedback.dart';
import '../../../services/live_session/live_session_controller.dart';
import '../../../services/notifications/session_notifier.dart';
import '../../../services/timer/timer_engine.dart';
import '../../../services/wakelock/screen_wake.dart';
import 'block_timer_spec.dart';
import 'session_item.dart';
import 'workout_session_event.dart';
import 'workout_session_state.dart';

/// Sessione di allenamento (RF-06).
///
/// Regole implementative (§5.1):
/// - **autosave**: ogni handler che muta lo stato persiste subito il
///   [WorkoutLog]. È così che si supera il crash test, non con un salvataggio
///   periodico;
/// - il Bloc si iscrive a [TimerEngine.stream] e ritrasmette come
///   [TimerTicked]: mai `emit` da una callback esterna;
/// - suoni, notifiche, wake lock e superficie di sistema passano da servizi
///   astratti, così la sessione resta testabile senza plugin.
///
/// La superficie di sistema ([LiveSessionController]) è l'unica sorgente di
/// eventi che può arrivare **a app spenta**: la conferma di una serie fatta
/// dalla schermata di blocco viene applicata con l'orario del tap, non con
/// quello del risveglio.
class WorkoutSessionBloc
    extends Bloc<WorkoutSessionEvent, WorkoutSessionState> {
  WorkoutSessionBloc({
    required PlanRepository planRepository,
    required WorkoutLogRepository logRepository,
    required TimerEngine timerEngine,
    required SessionFeedback feedback,
    required SessionNotifier notifier,
    required ScreenWake screenWake,
    required LiveSessionController liveSession,
    required LiveSessionLabels liveLabels,
    DateTime Function()? now,
  }) : _planRepository = planRepository,
       _logRepository = logRepository,
       _timerEngine = timerEngine,
       _feedback = feedback,
       _notifier = notifier,
       _screenWake = screenWake,
       _liveSession = liveSession,
       _liveLabels = liveLabels,
       _now = now ?? DateTime.now,
       super(const WorkoutSessionState()) {
    on<SessionStarted>(_onSessionStarted);
    on<SessionResumed>(_onSessionResumed);
    on<SetCompleted>(_onSetCompleted);
    on<LiveActionReceived>(_onLiveActionReceived);
    on<SetUnchecked>(_onSetUnchecked);
    on<SetLogged>(_onSetLogged);
    on<ExerciseFocused>(_onExerciseFocused);
    on<TimerRequested>(_onTimerRequested);
    on<TimerRequestDismissed>(_onTimerRequestDismissed);
    on<TimerTicked>(_onTimerTicked);
    on<TimerSignalled>(_onTimerSignalled);
    on<TimerStopped>(_onTimerStopped);
    on<AutoStartRestToggled>(_onAutoStartRestToggled);
    on<AppLifecycleChanged>(_onAppLifecycleChanged);
    on<SessionFinished>(_onSessionFinished);
    on<SessionErrorDismissed>(
      (event, emit) => emit(state.copyWith(errorMessage: null)),
    );

    _tickSub = _timerEngine.stream.listen((timer) => add(TimerTicked(timer)));
    _signalSub = _timerEngine.signals.listen(
      (signal) => add(TimerSignalled(signal)),
    );
    _liveSub = _liveSession.actions.listen(
      (action) => add(LiveActionReceived(action)),
    );
  }

  final PlanRepository _planRepository;
  final WorkoutLogRepository _logRepository;
  final TimerEngine _timerEngine;
  final SessionFeedback _feedback;
  final SessionNotifier _notifier;
  final ScreenWake _screenWake;
  final LiveSessionController _liveSession;
  final LiveSessionLabels _liveLabels;
  final DateTime Function() _now;

  late final StreamSubscription<TimerState> _tickSub;
  late final StreamSubscription<TimerSignal> _signalSub;
  late final StreamSubscription<LiveSessionAction> _liveSub;

  /// Azioni già applicate: la stessa conferma può arrivare due volte, dallo
  /// stream e dalla coda drenata al rientro in primo piano.
  final Set<String> _appliedLiveActions = {};

  /// Se le notifiche dei segnali sono già state programmate per questo
  /// passaggio in background. Scendendo, iOS manda `hidden` **e** `paused`, e
  /// risalendo passa di nuovo da `hidden`: senza questo, ognuno rifarebbe gli
  /// undici `cancel` più i dieci `zonedSchedule`, proprio nei millisecondi in
  /// cui iOS sta sospendendo il processo (spike S-01).
  ///
  /// Solo il verso "in background" si diserta: il rientro resta sempre
  /// attivo perché è anche l'unico momento in cui si ripulisce ciò che ha
  /// programmato un *altro* processo (il beep di fine recupero dell'isolate
  /// Android), e lì il Bloc nasce da zero senza sapere di essere stato via.
  bool _signalsScheduled = false;

  // --- apertura della sessione ---

  Future<void> _onSessionStarted(
    SessionStarted event,
    Emitter<WorkoutSessionState> emit,
  ) async {
    final plan = _planRepository.getById(event.planId);
    WorkoutDay? day;
    for (final candidate in plan?.days ?? const <WorkoutDay>[]) {
      if (candidate.id == event.dayId) {
        day = candidate;
        break;
      }
    }
    if (plan == null || day == null) {
      emit(state.copyWith(status: WorkoutSessionStatus.notFound));
      return;
    }

    try {
      final log = _logRepository.startSession(plan: plan, day: day);
      emit(
        state.copyWith(
          status: WorkoutSessionStatus.ready,
          log: log,
          day: day,
          lastPerformances: _loadLastPerformances(log),
          revision: state.revision + 1,
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          status: WorkoutSessionStatus.notFound,
          errorMessage: error.toString(),
        ),
      );
      return;
    }

    await _prepareDevices();
    _publishLive(starting: true);
    // Una coda rimasta da una sessione mai chiusa non deve sopravvivere a
    // questa: si svuota subito, e il filtro sul logId la scarta.
    await _drainLiveActions();
  }

  Future<void> _onSessionResumed(
    SessionResumed event,
    Emitter<WorkoutSessionState> emit,
  ) async {
    final log = _logRepository.getById(event.logId);
    if (log == null) {
      emit(state.copyWith(status: WorkoutSessionStatus.notFound));
      return;
    }

    final day = log.day.target;
    // La scheda può essere cambiata mentre la sessione era aperta: le entry
    // vengono riallineate alla sequenza attuale del giorno, senza perdere
    // quelle che non hanno più un esercizio corrispondente.
    if (day != null && _reconcileEntries(log, day)) {
      _save(log);
    }

    emit(
      state.copyWith(
        status: WorkoutSessionStatus.ready,
        log: log,
        day: day,
        lastPerformances: _loadLastPerformances(log),
        currentIndex: _firstUnfinishedIndex(log),
        revision: state.revision + 1,
      ),
    );

    await _prepareDevices();
    _publishLive(starting: true);
    // Il processo può essere stato ucciso con una conferma già data dalla
    // schermata di blocco: si applica adesso, con l'orario del tap.
    await _drainLiveActions();
  }

  Future<void> _prepareDevices() async {
    await _screenWake.enable();
    await _feedback.prepare();
    await _notifier.prepare();
  }

  /// Allinea le entry del log alla sequenza di esercizi del giorno.
  /// Ritorna `true` se qualcosa è cambiato (e quindi va persistito).
  bool _reconcileEntries(WorkoutLog log, WorkoutDay day) {
    final planned = flattenExercises(day);
    final pool = log.entries.toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final aligned = <LogEntry>[];
    var changed = false;

    for (final exercise in planned) {
      final index = pool.indexWhere(
        (entry) => entry.exerciseNameSnapshot == exercise.name,
      );
      if (index >= 0) {
        aligned.add(pool.removeAt(index));
      } else {
        final created = LogEntry(exerciseNameSnapshot: exercise.name);
        log.entries.add(created);
        aligned.add(created);
        changed = true;
      }
    }

    for (final orphan in pool) {
      if (orphan.sets.isEmpty) {
        // Esercizio tolto dalla scheda e mai svolto: niente da conservare.
        log.entries.remove(orphan);
        changed = true;
      } else {
        aligned.add(orphan);
      }
    }

    for (var i = 0; i < aligned.length; i++) {
      if (aligned[i].sortOrder != i) {
        aligned[i].sortOrder = i;
        changed = true;
      }
    }
    return changed;
  }

  Map<String, LastPerformance> _loadLastPerformances(WorkoutLog log) {
    final result = <String, LastPerformance>{};
    for (final entry in log.entries) {
      final name = entry.exerciseNameSnapshot;
      if (result.containsKey(name)) continue;
      final last = _logRepository.lastPerformance(name, excludeLogId: log.id);
      if (last != null) result[name] = last;
    }
    return result;
  }

  /// Alla ripresa si riparte dal primo esercizio senza serie registrate.
  int _firstUnfinishedIndex(WorkoutLog log) {
    final entries = log.entries.toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    for (var i = 0; i < entries.length; i++) {
      if (entries[i].sets.isEmpty) return i;
    }
    return 0;
  }

  // --- registrazione delle serie ---

  void _onSetCompleted(SetCompleted event, Emitter<WorkoutSessionState> emit) {
    _completeSet(
      entryIndex: event.entryIndex,
      setNumber: event.setNumber,
      at: _now(),
      emit: emit,
    );
  }

  /// Conferma arrivata da fuori: Live Activity o notifica persistente.
  ///
  /// Si scartano le azioni di un'altra sessione (una coda rimasta indietro non
  /// deve finire nel log sbagliato) e i doppioni, riconosciuti dall'id.
  void _onLiveActionReceived(
    LiveActionReceived event,
    Emitter<WorkoutSessionState> emit,
  ) {
    final action = event.action;
    if (state.log?.id != action.logId) return;
    if (!_appliedLiveActions.add(action.id)) return;

    switch (action.kind) {
      case LiveSessionActionKind.setCompleted:
        _completeSet(
          entryIndex: action.entryIndex,
          setNumber: action.setNumber,
          at: action.at,
          emit: emit,
        );
    }
  }

  /// Registra una serie svolta a [at] e, se previsto, avvia il recupero.
  void _completeSet({
    required int entryIndex,
    required int setNumber,
    required DateTime at,
    required Emitter<WorkoutSessionState> emit,
  }) {
    final item = _itemAt(entryIndex);
    if (item == null || item.isSetDone(setNumber)) return;

    final prefill = _prefillFor(item, setNumber);
    item.entry.sets.add(
      LogSet(
        setNumber: setNumber,
        reps: prefill.reps,
        weightKg: prefill.weightKg,
        completedAt: at,
      ),
    );

    _persist(emit, currentIndex: entryIndex);

    // L'avvio automatico non interrompe mai un timer già in corso: il
    // conflitto va risolto dall'utente, non silenziosamente (§9).
    if (!state.autoStartRest || _timerEngine.isRunning) return;
    final spec = restTimerSpec(item, label: item.name);
    if (spec == null) return;
    // Il recupero parte da quando la serie è finita. Se nel frattempo è già
    // scaduto — conferma dalla schermata di blocco e app riaperta molto dopo —
    // non si avvia un countdown che nascerebbe morto, con tanto di beep.
    if (!at.add(spec.total).isAfter(_now())) return;
    add(TimerRequested(spec, startedAt: at));
  }

  void _onSetUnchecked(SetUnchecked event, Emitter<WorkoutSessionState> emit) {
    final item = _itemAt(event.entryIndex);
    final set = item?.setNumbered(event.setNumber);
    if (item == null || set == null) return;

    item.entry.sets.remove(set);
    _persist(emit);
  }

  void _onSetLogged(SetLogged event, Emitter<WorkoutSessionState> emit) {
    final item = _itemAt(event.entryIndex);
    if (item == null) return;

    final existing = item.setNumbered(event.setNumber);
    if (existing == null) {
      item.entry.sets.add(
        LogSet(
          setNumber: event.setNumber,
          reps: event.reps,
          weightKg: event.weightKg,
          notes: event.notes,
          completedAt: _now(),
        ),
      );
    } else {
      existing
        ..reps = event.reps
        ..weightKg = event.weightKg
        ..notes = event.notes;
    }

    _persist(emit, currentIndex: event.entryIndex);
  }

  void _onExerciseFocused(
    ExerciseFocused event,
    Emitter<WorkoutSessionState> emit,
  ) {
    final all = state.items;
    if (all.isEmpty) return;
    emit(state.copyWith(currentIndex: event.index.clamp(0, all.length - 1)));
    _publishLive();
  }

  ({double? weightKg, String? reps}) _prefillFor(
    SessionItem item,
    int setNumber,
  ) {
    // Minimo attrito (RF-06): si riparte dall'ultimo valore usato in questa
    // sessione, poi da quello dell'ultima volta, infine dalla prescrizione.
    final earlier = item.completedSets
        .where((s) => s.setNumber < setNumber)
        .toList();
    if (earlier.isNotEmpty) {
      final previous = earlier.last;
      return (weightKg: previous.weightKg, reps: previous.reps);
    }

    final last = state.lastPerformances[item.name];
    if (last != null && last.sets.isNotEmpty) {
      final reference = last.sets.last;
      return (weightKg: reference.weightKg, reps: reference.reps);
    }

    return (weightKg: null, reps: item.exercise?.reps);
  }

  // --- timer ---

  void _onTimerRequested(
    TimerRequested event,
    Emitter<WorkoutSessionState> emit,
  ) {
    if (_timerEngine.isRunning && !event.force) {
      emit(state.copyWith(pendingTimerRequest: event.spec));
      return;
    }
    emit(state.copyWith(pendingTimerRequest: null));
    _timerEngine.start(event.spec, startedAt: event.startedAt);
    _publishLive();
  }

  void _onTimerRequestDismissed(
    TimerRequestDismissed event,
    Emitter<WorkoutSessionState> emit,
  ) {
    emit(state.copyWith(pendingTimerRequest: null));
  }

  void _onTimerTicked(TimerTicked event, Emitter<WorkoutSessionState> emit) {
    // La superficie di sistema non si aggiorna a ogni tick: il countdown lo
    // disegna il sistema partendo dall'istante di fine. Serve un solo
    // aggiornamento, quando quell'istante non è più nel futuro.
    final justFinished =
        event.timer.isFinished && !(state.timer?.isFinished ?? true);
    emit(state.copyWith(timer: event.timer));
    if (justFinished) _publishLive();
  }

  Future<void> _onTimerSignalled(
    TimerSignalled event,
    Emitter<WorkoutSessionState> emit,
  ) async {
    await _feedback.emit(event.signal);
  }

  void _onTimerStopped(TimerStopped event, Emitter<WorkoutSessionState> emit) {
    _timerEngine.stop();
    emit(state.copyWith(timer: null));
    _publishLive();
  }

  void _onAutoStartRestToggled(
    AutoStartRestToggled event,
    Emitter<WorkoutSessionState> emit,
  ) {
    emit(state.copyWith(autoStartRest: event.enabled));
  }

  // --- lifecycle ---

  Future<void> _onAppLifecycleChanged(
    AppLifecycleChanged event,
    Emitter<WorkoutSessionState> emit,
  ) async {
    if (event.toBackground) {
      if (_signalsScheduled) return;
      _signalsScheduled = true;
      final times = _timerEngine.upcomingSignalTimes(max: kMaxScheduledSignals);
      await _notifier.scheduleSignals(
        times,
        title: event.notificationTitle,
        body: event.notificationBody,
      );
      return;
    }

    _signalsScheduled = false;
    await _notifier.cancelPending();
    // Al rientro i tick sono stati sospesi dal sistema ma il tempo è passato:
    // lo stato si ricalcola dall'orologio (§7).
    _timerEngine.reconcile();

    // Le conferme date dalla schermata di blocco sono rimaste in coda: si
    // applicano adesso, con l'orario in cui l'utente le ha date.
    await _drainLiveActions();
  }

  /// Svuota la coda della superficie di sistema e applica quello che c'era.
  ///
  /// Su Android il tap sul pulsante della notifica passa *sempre* per
  /// l'isolate di background, anche ad app viva: la coda non è il ripiego, è
  /// la consegna. Perciò si drena sia all'apertura della sessione — il
  /// processo può essere morto nel frattempo, e lì nessun cambio di lifecycle
  /// arriva — sia a ogni rientro in primo piano.
  Future<void> _drainLiveActions() async {
    for (final action in await _liveSession.drainPendingActions()) {
      add(LiveActionReceived(action));
    }
  }

  // --- chiusura ---

  Future<void> _onSessionFinished(
    SessionFinished event,
    Emitter<WorkoutSessionState> emit,
  ) async {
    final log = state.log;
    if (log != null) {
      final notes = event.notes?.trim();
      log
        ..status = event.status
        ..finishedAt = _now()
        ..notes = (notes == null || notes.isEmpty) ? null : notes;
      _save(log);
    }

    _timerEngine.stop();
    emit(
      state.copyWith(
        status: WorkoutSessionStatus.finished,
        timer: null,
        revision: state.revision + 1,
      ),
    );

    await _notifier.cancelPending();
    await _liveSession.stop();
    await _screenWake.disable();
  }

  // --- superficie di sistema ---

  /// Ripubblica la sessione sulla schermata di blocco.
  ///
  /// Non si attende il risultato: la superficie è un di più, un errore di
  /// piattaforma non deve rallentare né interrompere la sessione (i servizi
  /// segnalano da sé i propri errori).
  void _publishLive({bool starting = false}) {
    final snapshot = _liveSnapshot();
    if (snapshot == null) return;
    unawaited(
      starting ? _liveSession.start(snapshot) : _liveSession.update(snapshot),
    );
  }

  /// Stato da mostrare fuori dall'app: l'esercizio con la prossima serie da
  /// spuntare e, se ce n'è uno, il countdown in corso.
  LiveSessionSnapshot? _liveSnapshot() {
    final log = state.log;
    if (log == null || state.status != WorkoutSessionStatus.ready) return null;

    final focus = _liveFocus();
    final item = focus?.item ?? state.currentItem;
    if (item == null) return null;

    final countdown = _liveCountdown();
    final restSpec = (focus != null && state.autoStartRest)
        ? restTimerSpec(focus.item)
        : null;

    // L'esercizio dopo viaggia insieme a questo: alla conferma dell'ultima
    // serie il nativo ci sposta sopra il banner da solo, invece di contare una
    // serie che non esiste.
    final next = focus == null ? null : _liveFocusAfter(focus.item);
    final nextRest = (next != null && state.autoStartRest)
        ? restTimerSpec(next.item)
        : null;

    return LiveSessionSnapshot(
      logId: log.id,
      exerciseName: item.name,
      entryIndex: item.index,
      setNumber: focus?.setNumber ?? 0,
      totalSets: item.displayedSets,
      canCompleteSet: focus != null,
      restSecondsOnComplete: restSpec?.total.inSeconds ?? 0,
      countdownStartsAt: countdown.startsAt,
      countdownEndsAt: countdown.endsAt,
      countdownLabel: countdown.label,
      nextExerciseName: next?.item.name,
      nextEntryIndex: next?.item.index ?? 0,
      nextSetNumber: next?.setNumber ?? 0,
      nextTotalSets: next?.item.displayedSets ?? 0,
      nextRestSecondsOnComplete: nextRest?.total.inSeconds ?? 0,
      labels: _liveLabels,
    );
  }

  /// Countdown da mostrare fuori dall'app.
  ///
  /// Si legge dal motore e non dallo stato: `start` lo aggiorna subito, mentre
  /// `state.timer` arriva solo col tick successivo. A recupero scaduto restano
  /// l'etichetta e nessun numero — il countdown lo disegna il sistema a
  /// partire dall'istante di fine, e a zero si ferma da solo.
  ({DateTime? startsAt, DateTime? endsAt, String? label}) _liveCountdown() {
    final timer = _timerEngine.current;
    if (timer == null || timer.spec.isCountUp) {
      return (startsAt: null, endsAt: null, label: null);
    }
    if (timer.isFinished) {
      return (
        startsAt: null,
        endsAt: null,
        label: timer.spec.kind == TimerKind.rest
            ? _liveLabels.restDoneLabel
            : null,
      );
    }
    return (
      startsAt: timer.startedAt,
      endsAt: timer.startedAt.add(timer.spec.total),
      label: timer.spec.kind == TimerKind.rest
          ? _liveLabels.restLabel
          : (timer.spec.label ?? _liveLabels.restLabel),
    );
  }

  /// Prossima serie da confermare: si parte dall'esercizio in evidenza e si
  /// prosegue in sequenza, perché il pulsante della schermata di blocco deve
  /// spuntare qualcosa di sensato anche quando l'esercizio corrente è finito.
  ({SessionItem item, int setNumber})? _liveFocus() {
    for (final pending in _livePendingSets()) {
      return pending;
    }
    return null;
  }

  /// Prima serie da spuntare **dopo** [item]: è quella su cui il nativo si
  /// sposta quando le serie di [item] finiscono. Le serie rimaste dello stesso
  /// esercizio le conta da sé.
  ({SessionItem item, int setNumber})? _liveFocusAfter(SessionItem item) {
    for (final pending in _livePendingSets()) {
      if (pending.item.index != item.index) return pending;
    }
    return null;
  }

  /// Serie ancora da spuntare, nell'ordine in cui si presentano all'utente:
  /// dall'esercizio in evidenza in avanti, poi si ricomincia da capo per
  /// raccogliere quelle saltate.
  Iterable<({SessionItem item, int setNumber})> _livePendingSets() sync* {
    final all = state.items;
    if (all.isEmpty) return;
    final start = state.currentIndex.clamp(0, all.length - 1);
    for (var offset = 0; offset < all.length; offset++) {
      final item = all[(start + offset) % all.length];
      // `checkableSets`, non `displayedSets`: un esercizio senza serie
      // prescritte ne ha comunque una da spuntare, e saltarlo qui lo faceva
      // sparire dal banner della schermata di blocco.
      final total = item.checkableSets;
      for (var setNumber = 1; setNumber <= total; setNumber++) {
        if (!item.isSetDone(setNumber)) {
          yield (item: item, setNumber: setNumber);
        }
      }
    }
  }

  // --- helper ---

  SessionItem? _itemAt(int index) {
    final all = state.items;
    if (index < 0 || index >= all.length) return null;
    return all[index];
  }

  /// Persiste e notifica la mutazione. L'autosave è sincrono di proposito:
  /// alla riapertura dopo un crash il log deve essere già a posto.
  void _persist(Emitter<WorkoutSessionState> emit, {int? currentIndex}) {
    final log = state.log;
    if (log == null) return;
    String? error;
    try {
      _logRepository.saveLog(log);
    } catch (e) {
      error = e.toString();
    }
    emit(
      state.copyWith(
        revision: state.revision + 1,
        currentIndex: currentIndex ?? state.currentIndex,
        errorMessage: error,
      ),
    );
    _publishLive();
  }

  void _save(WorkoutLog log) {
    try {
      _logRepository.saveLog(log);
    } catch (_) {
      // L'errore viene mostrato dal successivo _persist; qui non c'è un emit
      // disponibile e la sessione non deve interrompersi.
    }
  }

  @override
  Future<void> close() async {
    // Il timer si ferma per primo, in modo sincrono: uscendo dalla sessione
    // non deve restare un `Timer.periodic` vivo in attesa delle `await`.
    _timerEngine.stop();
    await _tickSub.cancel();
    await _signalSub.cancel();
    await _liveSub.cancel();
    await _notifier.cancelPending();
    // La superficie si spegne, non si smonta: il controller è dell'app, non
    // della singola sessione.
    await _liveSession.stop();
    await _screenWake.disable();
    return super.close();
  }
}
