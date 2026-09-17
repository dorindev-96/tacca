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
        restSecondsOnComplete: 0,
        labels: labels,
      ).toMap();

      expect(map['countdownStartsAt'], isNull);
      expect(map['countdownEndsAt'], isNull);
      expect(map['countdownLabel'], isNull);
    });
  });

  group('LiveSessionAction.tryParse', () {
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

    test('senza recupero configurato non nasce nessun countdown', () {
      final senzaRecupero = LiveSessionSnapshot(
        logId: 3,
        exerciseName: 'Panca piana',
        entryIndex: 1,
        setNumber: 1,
        totalSets: 4,
        canCompleteSet: true,
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
