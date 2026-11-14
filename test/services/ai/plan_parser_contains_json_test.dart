import 'package:flutter_test/flutter_test.dart';
import 'package:tacca/services/ai/plan_parser.dart';

/// Il criterio con cui l'import senza key smista un testo condiviso con
/// l'app: con un oggetto dentro è una risposta, senza è una scheda.
void main() {
  const parser = PlanParser();

  test('una risposta con il blocco JSON contiene un oggetto', () {
    expect(
      parser.containsJsonObject(
        'Ecco:\n```json\n{"name": "A", "days": []}\n```',
      ),
      isTrue,
    );
  });

  test('un oggetto nudo, anche non valido come scheda, conta lo stesso', () {
    // Decidere se è *valida* spetta a parse: qui basta che ci sia.
    expect(parser.containsJsonObject('{"name": "Senza giorni"}'), isTrue);
  });

  test('il testo di una scheda non contiene nessun oggetto', () {
    expect(
      parser.containsJsonObject('Giorno 1\nPanca 10x4 1\'30"\nSquat 10x4'),
      isFalse,
    );
  });

  test('una graffa lasciata aperta non è un oggetto', () {
    expect(parser.containsJsonObject('Panca {4 serie'), isFalse);
  });
}
