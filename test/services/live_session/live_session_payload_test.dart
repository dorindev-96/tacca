import 'package:flutter_test/flutter_test.dart';
import 'package:tacca/services/live_session/android_live_session_controller.dart';
import 'package:tacca/services/live_session/live_session_controller.dart';

/// Lo snapshot e le azioni attraversano un confine di piattaforma: quello che
/// si rompe qui si rompe in Swift, dove nessun test arriva.
void main() {
  const labels = LiveSessionLabels(
    title: 'Allenamento',
    setsLabel: 'Serie',
    completeAction: 'Serie fatta',
    roundsLabel: 'Giro',
    completeRoundAction: 'Giro fatto',
    restLabel: 'Recupero',
    restDoneLabel: 'Recupero finito',
  );

  final snapshot = LiveSessionSnapshot(
    logId: 3,
    exerciseName: 'Panca piana',
    entryIndex: 1,
    setNumber: 2,
    totalSets: 4,
    canCompleteSet: true,
    advancesToNext: false,
    restSecondsOnComplete: 90,
    countdownStartsAt: DateTime(2026, 8, 15, 18),
    countdownEndsAt: DateTime(2026, 8, 15, 18, 1, 30),
    countdownLabel: 'Recupero',
    labels: labels,
  );

  group('LiveSessionSnapshot', () {
    test('viaggia verso il nativo con date in millisecondi', () {
      final map = snapshot.toMap();

      expect(map['logId'], 3);
      expect(map['exerciseName'], 'Panca piana');
      expect(map['setNumber'], 2);
      expect(map['totalSets'], 4);
      expect(map['canCompleteSet'], isTrue);
      expect(map['restSecondsOnComplete'], 90);
      expect(
        map['countdownEndsAt'],
        DateTime(2026, 8, 15, 18, 1, 30).millisecondsSinceEpoch,
      );
      // Le etichette sono in linea con lo stato: il nativo legge una mappa
      // sola, non due.
      expect(map['completeAction'], 'Serie fatta');
    });

    test('senza countdown i campi temporali restano nulli', () {
      final map = LiveSessionSnapshot(
        logId: 1,
        exerciseName: 'Rematore',
        entryIndex: 0,
        setNumber: 1,
        totalSets: 3,
        canCompleteSet: true,
        advancesToNext: false,
        restSecondsOnComplete: 0,
        labels: labels,
      ).toMap();

      expect(map['countdownStartsAt'], isNull);
      expect(map['countdownEndsAt'], isNull);
      expect(map['countdownLabel'], isNull);
    });
  });

  group('LiveSessionAction.tryParse', () {
    test('accetta la conferma di un giro intero', () {
      // È la stringa scritta da `CompleteSetIntent.swift`: se cambia di là
      // senza cambiare qui, il giro confermato a telefono bloccato si perde.
      final action = LiveSessionAction.tryParse({
        'id': 'abc',
        'kind': 'roundCompleted',
        'logId': 3,
        'entryIndex': 0,
        'setNumber': 2,
        'at': DateTime(2026, 8, 15, 18).millisecondsSinceEpoch,
      });

      expect(action!.kind, LiveSessionActionKind.roundCompleted);
      expect(action.setNumber, 2);
    });

    test('accetta quello che manda il nativo', () {
      final action = LiveSessionAction.tryParse({
        'id': 'abc',
        'kind': 'setCompleted',
        'logId': 3,
        'entryIndex': 1,
        'setNumber': 2,
        'at': DateTime(2026, 8, 15, 18).millisecondsSinceEpoch,
      });

      expect(action, isNotNull);
      expect(action!.kind, LiveSessionActionKind.setCompleted);
      expect(action.at, DateTime(2026, 8, 15, 18));
    });

    test('rifiuta payload incompleti o di tipo sconosciuto', () {
      expect(LiveSessionAction.tryParse(null), isNull);
      expect(LiveSessionAction.tryParse('setCompleted'), isNull);
      expect(
        LiveSessionAction.tryParse({'id': 'abc', 'kind': 'setCompleted'}),
        isNull,
      );
      expect(
        LiveSessionAction.tryParse({
          'id': 'abc',
          'kind': 'boh',
          'logId': 1,
          'entryIndex': 0,
          'setNumber': 1,
          'at': 0,
        }),
        isNull,
      );
    });
  });

  group('LiveActionPayload (Android)', () {
    test('fa andata e ritorno dentro il payload della notifica', () {
      final encoded = LiveActionPayload.forSnapshot(
        snapshot,
        queuePath: '/tmp/actions.json',
      ).encode();

      final decoded = LiveActionPayload.tryParse(encoded);

      expect(decoded, isNotNull);
      expect(decoded!.queuePath, '/tmp/actions.json');
      // Non solo le coordinate della serie: torna indietro tutto lo stato
      // mostrato, perché l'isolate di background deve poterlo ridisegnare.
      expect(decoded.snapshot, snapshot);
    });

    test('su un giro intero l\'azione è la conferma del giro', () {
      final at = DateTime(2026, 8, 15, 18);
      final giro = LiveActionPayload.forSnapshot(
        LiveSessionSnapshot(
          logId: 3,
          exerciseName: 'Curl EZ + French press',
          entryIndex: 0,
          setNumber: 2,
          totalSets: 4,
          canCompleteSet: true,
          advancesToNext: false,
          restSecondsOnComplete: 60,
          completesRound: true,
          labels: labels,
        ),
        queuePath: '/tmp/actions.json',
      );
      final serie = LiveActionPayload.forSnapshot(
        snapshot,
        queuePath: '/tmp/actions.json',
      );

      final action = giro.toAction(at);
      expect(action.kind, LiveSessionActionKind.roundCompleted);
      expect(action.entryIndex, 0);
      expect(action.setNumber, 2);
      expect(serie.toAction(at).kind, LiveSessionActionKind.setCompleted);
      // E fa andata e ritorno nella coda come quella di una serie.
      expect(
        LiveSessionAction.tryParse(action.toMap())!.kind,
        LiveSessionActionKind.roundCompleted,
      );
    });

    test('l\'id dell\'azione identifica la serie e il momento del tap', () {
      final at = DateTime(2026, 8, 15, 18);
      final payload = LiveActionPayload.forSnapshot(
        snapshot,
        queuePath: '/tmp/actions.json',
      );

      expect(payload.toAction(at).id, payload.toAction(at).id);
      expect(
        payload.toAction(at).id,
        isNot(payload.toAction(at.add(const Duration(seconds: 1))).id),
      );
    });

    test('un payload rovinato non produce azioni', () {
      expect(LiveActionPayload.tryParse(null), isNull);
      expect(LiveActionPayload.tryParse(''), isNull);
      expect(LiveActionPayload.tryParse('non json'), isNull);
      expect(LiveActionPayload.tryParse('{"logId":3}'), isNull);
      expect(
        LiveActionPayload.tryParse('{"queuePath":"/tmp/a.json"}'),
        isNull,
        reason: 'senza stato non c\'è niente da ridisegnare',
      );
    });
  });

  group('LiveSessionSnapshot.tryParse', () {
    test('rilegge quello che ha scritto toMap', () {
      expect(LiveSessionSnapshot.tryParse(snapshot.toMap()), snapshot);
    });

    test('anche i flag dei blocchi a giri fanno andata e ritorno', () {
      // L'isolate di background di Android ricostruisce lo stato solo da
      // qui: se `advancesToNext` non sopravvive al viaggio, il tap a schermo
      // bloccato rimette il banner a contare i giri sullo stesso esercizio.
      // Lo snapshot condiviso qui sopra li ha entrambi falsi, quindi da solo
      // non direbbe niente.
      final giro = LiveSessionSnapshot(
        logId: 3,
        exerciseName: 'Curl EZ',
        entryIndex: 0,
        setNumber: 1,
        totalSets: 4,
        canCompleteSet: true,
        advancesToNext: true,
        restSecondsOnComplete: 0,
        nextExerciseName: 'French press',
        nextEntryIndex: 1,
        nextSetNumber: 1,
        nextTotalSets: 4,
        nextRestSecondsOnComplete: 60,
        nextAdvancesToNext: true,
        labels: labels,
      );

      expect(giro.toMap()['advancesToNext'], isTrue);
      expect(giro.toMap()['nextAdvancesToNext'], isTrue);
      expect(LiveSessionSnapshot.tryParse(giro.toMap()), giro);
    });

    test('anche il giro intero fa andata e ritorno', () {
      // Se `completesRound` si perde nel payload Android, l'isolate di
      // background ridisegna "Serie fatta" e mette in coda una serie sola.
      final giro = LiveSessionSnapshot(
        logId: 3,
        exerciseName: 'Curl EZ + French press',
        entryIndex: 0,
        setNumber: 2,
        totalSets: 4,
        canCompleteSet: true,
        advancesToNext: false,
        restSecondsOnComplete: 60,
        completesRound: true,
        nextExerciseName: 'Plank',
        nextEntryIndex: 2,
        nextSetNumber: 1,
        nextCompletesRound: false,
        labels: labels,
      );

      expect(giro.toMap()['completesRound'], isTrue);
      expect(giro.toMap()['nextCompletesRound'], isFalse);
      expect(giro.toMap()['completeRoundAction'], 'Giro fatto');
      expect(LiveSessionSnapshot.tryParse(giro.toMap()), giro);
    });

    test('una notifica di prima dei giri si rilegge lo stesso', () {
      // Pubblicata dalla versione precedente dell'app: niente etichette dei
      // giri, niente flag. Un tap lì sopra deve restare una serie confermata.
      final vecchia = snapshot.toMap()
        ..remove('roundsLabel')
        ..remove('completeRoundAction')
        ..remove('completesRound')
        ..remove('nextCompletesRound');

      final parsed = LiveSessionSnapshot.tryParse(vecchia)!;

      expect(parsed.completesRound, isFalse);
      expect(parsed.labels.roundsLabel, 'Serie');
      expect(parsed.labels.completeRoundAction, 'Serie fatta');
    });

    test('rifiuta una mappa senza stato o senza etichette', () {
      expect(LiveSessionSnapshot.tryParse(null), isNull);
      expect(LiveSessionSnapshot.tryParse({'logId': 3}), isNull);
      final senzaEtichette = snapshot.toMap()..remove('completeAction');
      expect(LiveSessionSnapshot.tryParse(senzaEtichette), isNull);
    });
  });

  /// Il passo che il sistema fa da solo alla conferma, senza l'app. La stessa
  /// aritmetica sta in `CompleteSetIntent.swift`, dove non arriva nessun test:
  /// se questi cambiano, va cambiato anche quello.
  group('LiveSessionSnapshot.afterSetCompleted', () {
    final tap = DateTime(2026, 8, 15, 18, 10);

    test('restando serie dello stesso esercizio conta avanti', () {
      final next = snapshot.afterSetCompleted(tap);

      expect(next.exerciseName, 'Panca piana');
      expect(next.setNumber, 3);
      expect(next.totalSets, 4);
      expect(next.canCompleteSet, isTrue);
      // Il recupero parte dal tap, non da quando l'app si sveglierà.
      expect(next.countdownStartsAt, tap);
      expect(next.countdownEndsAt, tap.add(const Duration(seconds: 90)));
      expect(next.countdownLabel, 'Recupero');
    });

    test('all\'ultima serie il banner passa all\'esercizio dopo', () {
      final ultima = LiveSessionSnapshot(
        logId: 3,
        exerciseName: 'Panca piana',
        entryIndex: 1,
        setNumber: 4,
        totalSets: 4,
        canCompleteSet: true,
        advancesToNext: false,
        restSecondsOnComplete: 90,
        nextExerciseName: 'Rematore',
        nextEntryIndex: 2,
        nextSetNumber: 1,
        nextTotalSets: 3,
        nextRestSecondsOnComplete: 60,
        labels: labels,
      );

      final next = ultima.afterSetCompleted(tap);

      expect(next.exerciseName, 'Rematore');
      expect(next.entryIndex, 2);
      expect(next.setNumber, 1);
      expect(next.totalSets, 3);
      expect(next.canCompleteSet, isTrue);
      expect(next.restSecondsOnComplete, 60);
      // Il recupero è ancora quello dell'esercizio appena finito.
      expect(next.countdownEndsAt, tap.add(const Duration(seconds: 90)));
      // Un passo solo: quale sia l'esercizio ancora dopo lo sa solo l'app.
      expect(next.nextExerciseName, isNull);
      expect(next.nextSetNumber, 0);
    });

    test('finite le serie il pulsante sparisce, senza inventarne una', () {
      final ultima = LiveSessionSnapshot(
        logId: 3,
        exerciseName: 'Rematore',
        entryIndex: 2,
        setNumber: 3,
        totalSets: 3,
        canCompleteSet: true,
        advancesToNext: false,
        restSecondsOnComplete: 0,
        labels: labels,
      );

      final next = ultima.afterSetCompleted(tap);

      expect(next.setNumber, 3);
      expect(next.canCompleteSet, isFalse);
      expect(next.countdownEndsAt, isNull);
      expect(next.countdownLabel, isNull);
    });

    test('un esercizio a serie unica passa subito a quello dopo', () {
      // Riscaldamento a tempo: nessuna serie prescritta, quindi `totalSets` è
      // zero e non c'è nessun "1 di quante" da contare avanti. Il gemello in
      // `CompleteSetIntent.swift` deve fare lo stesso salto.
      final aTempo = LiveSessionSnapshot(
        logId: 3,
        exerciseName: 'Camminata in salita',
        entryIndex: 0,
        setNumber: 1,
        totalSets: 0,
        canCompleteSet: true,
        advancesToNext: false,
        restSecondsOnComplete: 0,
        nextExerciseName: 'Back squat',
        nextEntryIndex: 1,
        nextSetNumber: 1,
        nextTotalSets: 3,
        nextRestSecondsOnComplete: 120,
        labels: labels,
      );

      final next = aTempo.afterSetCompleted(tap);

      expect(next.exerciseName, 'Back squat');
      expect(next.entryIndex, 1);
      expect(next.setNumber, 1);
      expect(next.totalSets, 3);
      expect(next.canCompleteSet, isTrue);
    });

    test('in un blocco a giri si passa all\'altro esercizio, non alla serie '
        'dopo', () {
      // `advancesToNext`: restano giri di questo esercizio (1 di 4), ma il
      // prossimo da fare è l'altro del superset. Contare avanti qui
      // registrerebbe un giro che l'utente non ha fatto. Il gemello in
      // `CompleteSetIntent.swift` ha lo stesso ramo.
      final giro = LiveSessionSnapshot(
        logId: 3,
        exerciseName: 'Curl EZ',
        entryIndex: 0,
        setNumber: 1,
        totalSets: 4,
        canCompleteSet: true,
        advancesToNext: true,
        restSecondsOnComplete: 0,
        nextExerciseName: 'French press',
        nextEntryIndex: 1,
        nextSetNumber: 1,
        nextTotalSets: 4,
        nextRestSecondsOnComplete: 60,
        nextAdvancesToNext: true,
        labels: labels,
      );

      final next = giro.afterSetCompleted(tap);

      expect(next.exerciseName, 'French press');
      expect(next.entryIndex, 1);
      expect(next.setNumber, 1);
      expect(next.restSecondsOnComplete, 60);
      // Anche di là la serie dopo è di un altro: senza lookahead il pulsante
      // sparisce, e il giro successivo lo ricalcola l'app.
      expect(next.advancesToNext, isTrue);
      expect(next.nextExerciseName, isNull);
      expect(next.canCompleteSet, isTrue);
    });

    test('il passo dopo quello, senza l\'app, non si inventa', () {
      final giro = LiveSessionSnapshot(
        logId: 3,
        exerciseName: 'French press',
        entryIndex: 1,
        setNumber: 1,
        totalSets: 4,
        canCompleteSet: true,
        advancesToNext: true,
        restSecondsOnComplete: 60,
        labels: labels,
      );

      final next = giro.afterSetCompleted(tap);

      // Niente "2/4" su French press: il giro 2 riparte da Curl EZ, e chi
      // sia lo sa solo il Bloc.
      expect(next.canCompleteSet, isFalse);
      expect(next.setNumber, 1);
      // Il recupero del giro parte lo stesso: quello non dipende dall'app.
      expect(next.countdownEndsAt, tap.add(const Duration(seconds: 60)));
    });

    test('in un superset conta avanti i giri, restando sul giro', () {
      // Il gemello in `CompleteSetIntent.swift`: lo stesso ramo che conta le
      // serie conta i giri, e il pulsante resta "Giro fatto".
      final giro = LiveSessionSnapshot(
        logId: 3,
        exerciseName: 'Trazioni + Dip',
        entryIndex: 1,
        setNumber: 1,
        totalSets: 3,
        canCompleteSet: true,
        advancesToNext: false,
        restSecondsOnComplete: 75,
        completesRound: true,
        nextExerciseName: 'Plank',
        nextEntryIndex: 3,
        nextSetNumber: 1,
        labels: labels,
      );

      final next = giro.afterSetCompleted(tap);

      expect(next.exerciseName, 'Trazioni + Dip');
      expect(next.entryIndex, 1);
      expect(next.setNumber, 2);
      expect(next.completesRound, isTrue);
      expect(next.countdownEndsAt, tap.add(const Duration(seconds: 75)));
      // Il lookahead resta: servirà finiti i giri.
      expect(next.nextExerciseName, 'Plank');
    });

    test('finiti i giri, sull\'esercizio dopo si torna alle serie', () {
      final ultimoGiro = LiveSessionSnapshot(
        logId: 3,
        exerciseName: 'Trazioni + Dip',
        entryIndex: 1,
        setNumber: 3,
        totalSets: 3,
        canCompleteSet: true,
        advancesToNext: false,
        restSecondsOnComplete: 75,
        completesRound: true,
        nextExerciseName: 'Plank',
        nextEntryIndex: 3,
        nextSetNumber: 1,
        nextCompletesRound: false,
        labels: labels,
      );

      final next = ultimoGiro.afterSetCompleted(tap);

      expect(next.exerciseName, 'Plank');
      expect(next.entryIndex, 3);
      expect(next.completesRound, isFalse);
      expect(next.canCompleteSet, isTrue);
    });

    test('arrivando su un superset il pulsante chiude il giro', () {
      final squat = LiveSessionSnapshot(
        logId: 3,
        exerciseName: 'Squat',
        entryIndex: 0,
        setNumber: 2,
        totalSets: 2,
        canCompleteSet: true,
        advancesToNext: false,
        restSecondsOnComplete: 90,
        nextExerciseName: 'Trazioni + Dip',
        nextEntryIndex: 1,
        nextSetNumber: 1,
        nextTotalSets: 3,
        nextRestSecondsOnComplete: 75,
        nextCompletesRound: true,
        labels: labels,
      );

      final next = squat.afterSetCompleted(tap);

      expect(next.exerciseName, 'Trazioni + Dip');
      expect(next.completesRound, isTrue);
      expect(next.restSecondsOnComplete, 75);
      expect(next.nextCompletesRound, isFalse);
    });

    test('senza recupero configurato non nasce nessun countdown', () {
      final senzaRecupero = LiveSessionSnapshot(
        logId: 3,
        exerciseName: 'Panca piana',
        entryIndex: 1,
        setNumber: 1,
        totalSets: 4,
        canCompleteSet: true,
        advancesToNext: false,
        restSecondsOnComplete: 0,
        labels: labels,
      );

      final next = senzaRecupero.afterSetCompleted(tap);

      expect(next.setNumber, 2);
      expect(next.countdownStartsAt, isNull);
      expect(next.countdownEndsAt, isNull);
    });
  });
}
