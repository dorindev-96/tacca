import 'dart:async';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tacca/services/live_session/android_live_session_controller.dart';
import 'package:tacca/services/live_session/live_session_controller.dart';
import 'package:tacca/services/live_session/pending_action_queue.dart';
import 'package:tacca/services/notifications/notification_host.dart';

/// La conferma dal pulsante della notifica arriva *sempre* dall'isolate di
/// background, anche ad app viva: la coda su file è la consegna, non il
/// ripiego. Qui si verifica che si legga anche a processo appena ripartito,
/// quando nessuno ha ancora pubblicato niente — pubblicare tocca un canale di
/// piattaforma, che su host non esiste.
void main() {
  late Directory dir;
  late _UnusableHost host;
  late AndroidLiveSessionController controller;

  final action = LiveSessionAction(
    id: 'azione-1',
    kind: LiveSessionActionKind.setCompleted,
    logId: 7,
    entryIndex: 0,
    setNumber: 2,
    at: DateTime(2026, 8, 15, 18, 30),
  );

  void queueUp() => PendingActionQueue(
    File('${dir.path}/$kPendingActionsFileName'),
  ).append(action);

  setUp(() {
    dir = Directory.systemTemp.createTempSync('tacca_live_android');
    host = _UnusableHost();
    controller = AndroidLiveSessionController(
      host: host,
      supportDirectory: () async => dir,
    );
  });

  tearDown(() async {
    await controller.dispose();
    dir.deleteSync(recursive: true);
  });

  test(
    'la coda si legge anche se la sessione non è mai stata avviata',
    () async {
      // Il tap è arrivato a processo ucciso: l'isolate di background ha
      // scritto e basta. Alla riapertura il Bloc drena prima che la notifica
      // esista, e lì `start` non è ancora passata di qui.
      queueUp();

      final drained = await controller.drainPendingActions();

      expect(drained.map((a) => a.id), ['azione-1']);
      expect(drained.single.at, DateTime(2026, 8, 15, 18, 30));
      expect(drained.single.setNumber, 2);
    },
  );

  test('drenare due volte non registra la stessa serie due volte', () async {
    queueUp();

    expect(await controller.drainPendingActions(), hasLength(1));
    expect(await controller.drainPendingActions(), isEmpty);
  });

  test('senza sessione aperta un aggiornamento non pubblica niente', () async {
    await controller.update(_snapshot);

    expect(host.pluginTouched, isFalse);
    expect(host.initCount, 0);
  });

  test('se le notifiche non sono disponibili non si pubblica', () async {
    // `ensureInitialized` fallisce (permesso negato, plugin assente): né
    // l'avvio né gli aggiornamenti che seguono devono arrivare al plugin.
    await controller.start(_snapshot);
    await controller.update(_snapshot);

    expect(host.initCount, 1);
    expect(host.pluginTouched, isFalse);
  });
}

const _snapshot = LiveSessionSnapshot(
  logId: 7,
  exerciseName: 'Panca piana',
  entryIndex: 0,
  setNumber: 2,
  totalSets: 4,
  canCompleteSet: true,
  advancesToNext: false,
  restSecondsOnComplete: 90,
  labels: LiveSessionLabels(
    title: 'Allenamento',
    setsLabel: 'Serie',
    completeAction: 'Serie fatta',
    restLabel: 'Recupero',
    restDoneLabel: 'Recupero finito',
  ),
);

/// Host che non si può usare: qualunque strada arrivi al plugin fallisce il
/// test invece di finire in un canale di piattaforma che su host non esiste.
class _UnusableHost implements NotificationHost {
  bool pluginTouched = false;
  int initCount = 0;

  @override
  FlutterLocalNotificationsPlugin get plugin {
    pluginTouched = true;
    throw StateError('il plugin non deve essere toccato');
  }

  @override
  DidReceiveBackgroundNotificationResponseCallback? get onBackgroundResponse =>
      null;

  @override
  Stream<NotificationResponse> get responses => const Stream.empty();

  @override
  Future<bool> ensureInitialized() async {
    initCount++;
    return false;
  }

  @override
  Future<void> dispose() async {}
}
