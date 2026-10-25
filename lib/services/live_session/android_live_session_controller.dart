import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';
import 'package:timezone/timezone.dart' as tz;

import '../notifications/notification_host.dart';
import '../notifications/session_notifier.dart';
import 'live_session_controller.dart';
import 'pending_action_queue.dart';

/// Id dell'azione "serie fatta" sulla notifica di sessione. Vive fuori dalla
/// classe perché lo legge anche l'isolate di background, che non ha istanze.
const String kCompleteSetActionId = 'live_session.complete_set';

/// Nome del file della coda dentro la directory di supporto dell'app.
const String kPendingActionsFileName = 'live_session_actions.json';

/// Id della notifica di sessione: fuori dall'intervallo dei segnali del timer
/// (9100+) e fuori dalla classe, perché la ridisegna anche l'isolate di
/// background.
const int _liveNotificationId = 9200;

/// Notifica persistente della sessione su Android.
///
/// È l'equivalente della Live Activity di iOS con i mezzi del sistema: una
/// notifica `ongoing`, con il countdown disegnato dal sistema
/// (`usesChronometer` + `chronometerCountDown`, quindi esatto anche a processo
/// fermo) e un pulsante che conferma la serie senza aprire l'app.
///
/// Non c'è un foreground service: la notifica sopravvive comunque alla morte
/// del processo e il countdown lo disegna il sistema. Al tap sul pulsante non
/// risponde questa classe ma [liveSessionActionBackground], che gira in un
/// isolate a sé e fa da solo quello che farebbe l'app.
class AndroidLiveSessionController implements LiveSessionController {
  AndroidLiveSessionController({
    required NotificationHost host,
    Future<Directory> Function()? supportDirectory,
    DateTime Function()? now,
  }) : _host = host,
       _supportDirectory = supportDirectory ?? getApplicationSupportDirectory,
       _now = now ?? DateTime.now;

  final NotificationHost _host;
  final Future<Directory> Function() _supportDirectory;
  final DateTime Function() _now;

  final _actions = StreamController<LiveSessionAction>.broadcast();

  PendingActionQueue? _queue;
  StreamSubscription<NotificationResponse>? _responses;
  LiveSessionSnapshot? _shown;

  /// Apertura della sessione: `null` fuori da una sessione, altrimenti l'esito
  /// dell'inizializzazione. È anche il punto su cui [update] si sincronizza.
  Future<bool>? _startup;

  @override
  Stream<LiveSessionAction> get actions => _actions.stream;

  @override
  Future<bool> isSupported() => _host.ensureInitialized();

  @override
  Future<void> start(LiveSessionSnapshot snapshot) async {
    await (_startup = _start(snapshot));
  }

  /// Non lancia mai: [_startup] viene atteso da [update], e la superficie di
  /// sistema non deve poter far cadere la sessione.
  Future<bool> _start(LiveSessionSnapshot snapshot) async {
    try {
      if (!await _host.ensureInitialized()) return false;
      await _ensureQueue();
      _responses ??= _host.responses.listen(_onResponse);
      await _publish(snapshot);
      return true;
    } catch (error, stackTrace) {
      reportNotificationError('notifica di sessione', error, stackTrace);
      return false;
    }
  }

  @override
  Future<void> update(LiveSessionSnapshot snapshot) async {
    final startup = _startup;
    // Fuori da una sessione aperta non si pubblica nulla. Se l'apertura è
    // ancora in volo la si aspetta invece di scavalcarla: succede quando la
    // coda viene applicata subito dopo l'apertura della sessione, e un
    // aggiornamento scartato lì lascerebbe il banner indietro di una serie.
    if (startup == null || !await startup) return;
    // Uno snapshot identico non merita un ridisegno.
    if (snapshot == _shown) return;
    await _publish(snapshot);
  }

  @override
  Future<void> stop() async {
    _startup = null;
    _shown = null;
    _queue?.clear();
    _queue = null;
    try {
      await _host.plugin.cancel(id: _liveNotificationId);
    } catch (error, stackTrace) {
      reportNotificationError('notifica di sessione', error, stackTrace);
    }
  }

  @override
  Future<List<LiveSessionAction>> drainPendingActions() async {
    // Il Bloc aspetta questa risposta per aprire la sessione: una directory
    // di supporto irraggiungibile costa le conferme in coda, non l'apertura.
    try {
      return (await _ensureQueue()).drain();
    } catch (error, stackTrace) {
      reportNotificationError('coda della sessione', error, stackTrace);
      return const [];
    }
  }

  /// La coda è un file: si legge anche prima che la notifica esista. È
  /// quello che serve quando il processo è stato ucciso — la conferma è già
  /// in coda e nessuno ha ancora chiamato [start].
  Future<PendingActionQueue> _ensureQueue() async =>
      _queue ??= PendingActionQueue(
        File('${(await _supportDirectory()).path}/$kPendingActionsFileName'),
      );

  @override
  Future<void> dispose() async {
    await _responses?.cancel();
    await _actions.close();
  }

  Future<void> _publish(LiveSessionSnapshot snapshot) async {
    try {
      await showLiveSessionNotification(
        _host.plugin,
        snapshot,
        queuePath: _queue?.file.path ?? '',
      );
      _shown = snapshot;
    } catch (error, stackTrace) {
      reportNotificationError('notifica di sessione', error, stackTrace);
    }
  }

  /// Rete di sicurezza: in pratica non scatta. Con `showsUserInterface: false`
  /// il plugin manda il tap a `ActionBroadcastReceiver` — dichiarato nel
  /// manifest dell'app, senza non arriva da nessuna parte — e da lì a
  /// [liveSessionActionBackground], anche ad app viva. La strada vera è
  /// quindi sempre la coda, drenata all'apertura della sessione e al rientro
  /// in primo piano.
  void _onResponse(NotificationResponse response) {
    if (response.actionId != kCompleteSetActionId) return;
    final payload = LiveActionPayload.tryParse(response.payload);
    if (payload == null || _actions.isClosed) return;
    _actions.add(payload.toAction(_now()));
  }
}

/// Dati che viaggiano nel payload della notifica.
///
/// Porta lo **stato mostrato**, non solo le coordinate della serie: l'isolate
/// di background non ha nessun altro modo di sapere cosa c'è scritto sulla
/// notifica che l'utente ha appena premuto, e senza quello non può
/// ridisegnarla. È il posto che su iOS occupa `Activity.content.state`.
///
/// Contiene anche il percorso della coda: così l'isolate non ha bisogno di
/// `path_provider` — e quindi di plugin registrati — per sapere dove scrivere.
class LiveActionPayload {
  const LiveActionPayload({required this.queuePath, required this.snapshot});

  factory LiveActionPayload.forSnapshot(
    LiveSessionSnapshot snapshot, {
    required String queuePath,
  }) => LiveActionPayload(queuePath: queuePath, snapshot: snapshot);

  final String queuePath;
  final LiveSessionSnapshot snapshot;

  String encode() =>
      jsonEncode({'queuePath': queuePath, 'snapshot': snapshot.toMap()});

  static LiveActionPayload? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final queuePath = decoded['queuePath'];
      final snapshot = LiveSessionSnapshot.tryParse(decoded['snapshot']);
      if (queuePath is! String || snapshot == null) return null;
      return LiveActionPayload(queuePath: queuePath, snapshot: snapshot);
    } catch (_) {
      return null;
    }
  }

  /// La conferma di ciò che la notifica mostrava: una serie, o il giro intero
  /// di un superset.
  LiveSessionAction toAction(DateTime at) => LiveSessionAction(
    // Deterministico: la stessa conferma consegnata due volte (stream e coda)
    // viene riconosciuta e applicata una volta sola.
    id:
        '${snapshot.completesRound ? 'round' : 'set'}'
        '-${snapshot.logId}-${snapshot.entryIndex}-${snapshot.setNumber}'
        '-${at.millisecondsSinceEpoch}',
    kind: snapshot.completesRound
        ? LiveSessionActionKind.roundCompleted
        : LiveSessionActionKind.setCompleted,
    logId: snapshot.logId,
    entryIndex: snapshot.entryIndex,
    setNumber: snapshot.setNumber,
    at: at,
  );
}

/// Disegna la notifica di sessione a partire da [snapshot].
///
/// Sta fuori dalla classe perché non la disegna solo il controller: la
/// ridisegna anche l'isolate di background alla conferma di una serie, dove
/// non esistono né controller né [NotificationHost] e il plugin è un'istanza
/// nuova sul motore appena acceso.
Future<void> showLiveSessionNotification(
  FlutterLocalNotificationsPlugin plugin,
  LiveSessionSnapshot snapshot, {
  required String queuePath,
}) {
  final countdown = snapshot.countdownEndsAt;
  final label = snapshot.countdownLabel;
  final labels = snapshot.labels;
  // In un superset si contano i giri, non le serie.
  final unit = snapshot.completesRound ? labels.roundsLabel : labels.setsLabel;
  // A serie esaurite non c'è nessun numero da mostrare: resta il titolo.
  final sets = switch (snapshot) {
    _ when snapshot.setNumber <= 0 => labels.title,
    _ when snapshot.totalSets > 0 =>
      '$unit ${snapshot.setNumber}/${snapshot.totalSets}',
    _ => '$unit ${snapshot.setNumber}',
  };
  final details = AndroidNotificationDetails(
    'workout_live',
    'Sessione in corso',
    channelDescription:
        'Esercizio corrente e recupero, con la conferma della serie',
    // Bassa importanza: è uno stato, non un allarme. Il beep di fine
    // recupero resta quello del canale dei timer.
    importance: Importance.low,
    priority: Priority.low,
    category: AndroidNotificationCategory.workout,
    ongoing: true,
    autoCancel: false,
    onlyAlertOnce: true,
    playSound: false,
    enableVibration: false,
    visibility: NotificationVisibility.public,
    subText: labels.title,
    showWhen: countdown != null,
    when: countdown?.millisecondsSinceEpoch,
    usesChronometer: countdown != null,
    chronometerCountDown: countdown != null,
    actions: [
      if (snapshot.canCompleteSet)
        AndroidNotificationAction(
          kCompleteSetActionId,
          snapshot.completesRound
              ? labels.completeRoundAction
              : labels.completeAction,
          // Il pulsante non deve aprire l'app né far sparire la notifica:
          // è tutto il senso della cosa.
          showsUserInterface: false,
          cancelNotification: false,
        ),
    ],
  );

  return plugin.show(
    id: _liveNotificationId,
    title: snapshot.exerciseName,
    body: label != null ? '$label · $sets' : sets,
    notificationDetails: NotificationDetails(android: details),
    payload: LiveActionPayload.forSnapshot(
      snapshot,
      queuePath: queuePath,
    ).encode(),
  );
}

/// Conferma premuta sulla notifica: gira in un isolate senza Bloc, senza
/// database e senza l'app. Il broadcast arriva anche a processo ucciso, e ci
/// passa comunque anche ad app viva: il plugin non consegna mai le azioni
/// all'isolate principale.
///
/// Fa le stesse tre cose di `CompleteSetIntent.swift`, nello stesso ordine:
///
/// 1. mette l'azione in coda, **in modo sincrono** — è l'unica che non può
///    fallire senza perdere il lavoro dell'utente;
/// 2. ridisegna la notifica con la serie dopo e il recupero già avviato, così
///    il tap ha un effetto visibile senza aprire l'app;
/// 3. programma il beep di fine recupero, perché lo darebbe l'app e l'app non
///    è sveglia.
///
/// I punti 2 e 3 girano su un motore che il sistema può spegnere appena il
/// broadcast è servito: se non arrivano in fondo si perde l'aggiornamento del
/// banner, non la serie. L'app, al rientro, drena la coda e ricalcola tutto —
/// ed è lei che annulla il beep, perché l'id appartiene a `SessionNotifier`.
@pragma('vm:entry-point')
Future<void> liveSessionActionBackground(NotificationResponse response) async {
  if (response.actionId != kCompleteSetActionId) return;
  final payload = LiveActionPayload.tryParse(response.payload);
  if (payload == null || payload.queuePath.isEmpty) return;
  final shown = payload.snapshot;
  // Il pulsante non esiste quando non c'è più niente da spuntare: un tap su
  // una notifica rimasta indietro non deve inventare una serie.
  if (!shown.canCompleteSet) return;

  final at = DateTime.now();
  PendingActionQueue(File(payload.queuePath)).append(payload.toAction(at));

  // I plugin sono registrati anche qui — il motore di background lo fa da sé —
  // ma non c'è nessuna `initialize` da rifare: l'icona di default l'ha già
  // salvata l'app, e reinizializzare vorrebbe dire riscrivere gli handle delle
  // callback da un isolate che sta per spegnersi.
  final plugin = FlutterLocalNotificationsPlugin();
  try {
    await showLiveSessionNotification(
      plugin,
      shown.afterSetCompleted(at),
      queuePath: payload.queuePath,
    );
  } catch (error, stackTrace) {
    reportNotificationError('notifica di sessione', error, stackTrace);
  }

  if (shown.restSecondsOnComplete <= 0) return;
  try {
    await plugin.zonedSchedule(
      id: kBackgroundRestReminderId,
      // `tz.UTC` esiste senza inizializzare il database dei fusi orari: qui
      // serve un istante assoluto, non un orario locale da mostrare.
      scheduledDate: tz.TZDateTime.from(
        at.add(Duration(seconds: shown.restSecondsOnComplete)),
        tz.UTC,
      ),
      title: shown.labels.title,
      body: shown.labels.restDoneLabel,
      notificationDetails: kTimerSignalDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  } catch (error, stackTrace) {
    reportNotificationError('fine recupero', error, stackTrace);
  }
}
