import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tacca/services/notifications/session_notifier.dart';
import 'package:tacca/services/timer/timer_engine.dart';

/// Quanto un istante programmato può discostarsi da quello vero: né iOS né
/// Android scendono sotto il secondo (spike S-01).
const _tolleranza = Duration(seconds: 1);

/// Un orario con una frazione di secondo qualsiasi, come lo produce il tocco
/// dell'utente: è da lì che nasce tutto il problema.
final _start = DateTime(2026, 8, 15, 18, 0, 0, 750);

void main() {
  group('scheduledInstantFor (spike S-01)', () {
    test('non anticipa mai il segnale', () {
      // Il sistema tronca: senza arrotondamento in avanti questo istante
      // suonerebbe alle 18:01:30.000, cioè 750ms prima della fine del
      // recupero. Sul recupero l'anticipo è la direzione che fa male.
      final vero = _start.add(const Duration(seconds: 90));
      final programmato = scheduledInstantFor(vero);

      expect(programmato.isBefore(vero), isFalse);
      expect(programmato, DateTime(2026, 8, 15, 18, 1, 31));
    });

    test('resta dentro il secondo e cade su un secondo intero', () {
      // Ogni frazione possibile, non solo quella comoda.
      for (var ms = 0; ms < 1000; ms++) {
        final vero = DateTime(2026, 8, 15, 18, 0, 0, ms);
        final programmato = scheduledInstantFor(vero);

        expect(
          programmato.isBefore(vero),
          isFalse,
          reason: 'con $ms ms il segnale arriverebbe in anticipo',
        );
        expect(
          programmato.difference(vero),
          lessThan(_tolleranza),
          reason: 'con $ms ms il ritardo supera il secondo',
        );
        expect(programmato.millisecond, 0);
        expect(programmato.microsecond, 0);
      }
    });

    test('un istante già intero resta dov\'è', () {
      final intero = DateTime(2026, 8, 15, 18, 1, 30);
      expect(scheduledInstantFor(intero), intero);
      // Anche i microsecondi contano: 1µs oltre il secondo è già "non intero".
      final quasi = intero.add(const Duration(microseconds: 1));
      expect(scheduledInstantFor(quasi), intero.add(const Duration(seconds: 1)));
    });

    test('nessun segnale di un EMOM viene anticipato', () {
      fakeAsync((async) {
        final engine = TimerEngine(now: () => _start.add(async.elapsed));
        engine.start(
          TimerSpec.emom(
            interval: const Duration(seconds: 60),
            total: const Duration(minutes: 5),
          ),
        );

        final veri = engine.upcomingSignalTimes(max: kMaxScheduledSignals);
        expect(veri, isNotEmpty);

        var precedente = DateTime(2000);
        for (final vero in veri) {
          final programmato = scheduledInstantFor(vero);
          expect(
            programmato.isBefore(vero),
            isFalse,
            reason: '$vero verrebbe anticipato',
          );
          expect(programmato.difference(vero), lessThan(_tolleranza));
          // L'ordine cronologico che il sistema riceve resta quello vero:
          // gli id delle notifiche sono assegnati per posizione.
          expect(programmato.isAfter(precedente), isTrue);
          precedente = programmato;
        }

        engine.dispose();
        async.flushMicrotasks();
      });
    });
  });
}
