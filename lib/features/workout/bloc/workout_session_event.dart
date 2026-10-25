import '../../../data/entities/workout_log.dart';
import '../../../services/live_session/live_session_controller.dart';
import '../../../services/timer/timer_engine.dart';

/// Eventi della sessione di allenamento (§5.1).
///
/// È l'unica feature modellata come Bloc invece che come Cubit: gli input
/// arrivano da utente, [TimerEngine] e lifecycle dell'app, e il loro ordine
/// conta.
sealed class WorkoutSessionEvent {
  const WorkoutSessionEvent();
}

/// Nuova sessione su un giorno di una scheda: crea e persiste subito il log.
final class SessionStarted extends WorkoutSessionEvent {
  const SessionStarted({required this.planId, required this.dayId});

  final int planId;
  final int dayId;
}

/// Ripresa di una sessione lasciata aperta (chiusura o crash dell'app).
final class SessionResumed extends WorkoutSessionEvent {
  const SessionResumed(this.logId);

  final int logId;
}

/// Spunta di una serie: registra la serie e, se abilitato, avvia il recupero.
final class SetCompleted extends WorkoutSessionEvent {
  const SetCompleted({required this.entryIndex, required this.setNumber});

  final int entryIndex;
  final int setNumber;
}

/// Giro concluso in un superset o in un circuito: spunta in un colpo la serie
/// [round] di ogni esercizio del gruppo che non l'ha ancora, e avvia il
/// recupero del giro.
///
/// [entryIndex] è un esercizio qualsiasi del gruppo. Fuori da un gruppo a
/// giri vale come [SetCompleted].
final class RoundCompleted extends WorkoutSessionEvent {
  const RoundCompleted({required this.entryIndex, required this.round});

  final int entryIndex;
  final int round;
}

/// Spunta tolta: la serie registrata viene rimossa.
final class SetUnchecked extends WorkoutSessionEvent {
  const SetUnchecked({required this.entryIndex, required this.setNumber});

  final int entryIndex;
  final int setNumber;
}

/// Peso/ripetizioni effettivi di una serie (log rapido, RF-06).
final class SetLogged extends WorkoutSessionEvent {
  const SetLogged({
    required this.entryIndex,
    required this.setNumber,
    this.weightKg,
    this.reps,
    this.notes,
  });

  final int entryIndex;
  final int setNumber;
  final double? weightKg;
  final String? reps;
  final String? notes;
}

/// Esercizio corrente (quello evidenziato nella vista palestra).
final class ExerciseFocused extends WorkoutSessionEvent {
  const ExerciseFocused(this.index);

  final int index;
}

/// Conferma arrivata dalla superficie di sistema (Live Activity su iOS,
/// notifica persistente su Android): la serie è stata spuntata a telefono
/// bloccato, senza aprire l'app.
final class LiveActionReceived extends WorkoutSessionEvent {
  const LiveActionReceived(this.action);

  final LiveSessionAction action;
}

/// Richiesta di avvio di un timer. Con un timer già in corso la richiesta
/// viene messa in attesa di conferma (analisi funzionale §9), a meno di
/// [force].
final class TimerRequested extends WorkoutSessionEvent {
  const TimerRequested(this.spec, {this.force = false, this.startedAt});

  final TimerSpec spec;
  final bool force;

  /// Istante di partenza del timer, quando non è "adesso": una serie
  /// confermata dalla schermata di blocco fa partire il recupero da quel tap,
  /// non da quando l'app si risveglia.
  final DateTime? startedAt;
}

/// L'utente ha rinunciato a sostituire il timer in corso.
final class TimerRequestDismissed extends WorkoutSessionEvent {
  const TimerRequestDismissed();
}

/// Aggiornamento periodico ritrasmesso dal [TimerEngine].
final class TimerTicked extends WorkoutSessionEvent {
  const TimerTicked(this.timer);

  final TimerState timer;
}

/// Segnale del timer da rendere percepibile (beep + vibrazione).
final class TimerSignalled extends WorkoutSessionEvent {
  const TimerSignalled(this.signal);

  final TimerSignal signal;
}

/// Arresto manuale del timer in corso.
final class TimerStopped extends WorkoutSessionEvent {
  const TimerStopped();
}

/// Avvio automatico del recupero dopo la spunta di una serie (RF-06).
final class AutoStartRestToggled extends WorkoutSessionEvent {
  const AutoStartRestToggled(this.enabled);

  final bool enabled;
}

/// Passaggio in background/foreground: programma o annulla le notifiche dei
/// segnali e riallinea il timer all'orologio (§7).
///
/// Titolo e testo della notifica arrivano dalla UI perché le stringhe utente
/// vivono negli ARB e il Bloc non ha un [BuildContext].
final class AppLifecycleChanged extends WorkoutSessionEvent {
  const AppLifecycleChanged({
    required this.toBackground,
    this.notificationTitle = '',
    this.notificationBody = '',
  });

  final bool toBackground;
  final String notificationTitle;
  final String notificationBody;
}

/// Chiude il messaggio di errore mostrato in sessione.
final class SessionErrorDismissed extends WorkoutSessionEvent {
  const SessionErrorDismissed();
}

/// Chiusura della sessione con esito [status] (completata o interrotta).
final class SessionFinished extends WorkoutSessionEvent {
  const SessionFinished({required this.status, this.notes});

  final WorkoutStatus status;
  final String? notes;
}
