import 'package:tacca/data/entities/block.dart';
import 'package:tacca/services/ai/plan_parser.dart';
import 'package:tacca/services/ai/prompts.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fixture conforme allo schema §5.3 dell'analisi funzionale, con tutti i
/// tipi di blocco temporizzati e un freeText.
const _validJson = '''
{
  "name": "Upper/Lower — Fase 2",
  "notes": "Settimane 5-8",
  "days": [
    {
      "label": "Giorno A — Upper",
      "blocks": [
        {
          "type": "standard",
          "exercises": [
            { "name": "Panca piana", "sets": 4, "reps": "6-8", "load": "80kg", "restSeconds": 150 },
            { "name": "Rematore bilanciere", "sets": 4, "reps": "8", "restSeconds": 120 }
          ]
        },
        {
          "type": "emom",
          "intervalSeconds": 60,
          "totalMinutes": 10,
          "notes": "Minuti dispari trazioni, pari dip",
          "exercises": [
            { "name": "Trazioni", "reps": "5" },
            { "name": "Dip", "reps": "8" }
          ]
        },
        { "type": "freeText", "content": "Finisher a scelta: 5' corda" }
      ]
    },
    {
      "label": "Giorno B — Lower",
      "blocks": [
        { "type": "amrap", "durationSeconds": 900, "exercises": [ { "name": "Squat", "reps": "10" } ] },
        { "type": "tabata", "workSeconds": 20, "restSeconds": 10, "rounds": 8, "exercises": [ { "name": "Burpees" } ] },
        { "type": "circuit", "rounds": 3, "restBetweenRoundsSeconds": 60, "exercises": [ { "name": "Affondi" } ] },
        { "type": "forTime", "timeCapSeconds": 600, "exercises": [ { "name": "Row" } ] }
      ]
    }
  ]
}
''';

void main() {
  const parser = PlanParser();

  group('PlanParser.parse', () {
    test('decodifica un JSON valido con tutti i tipi di blocco', () {
      final dto = parser.parse(_validJson);

      expect(dto.name, 'Upper/Lower — Fase 2');
      expect(dto.days, hasLength(2));
      expect(dto.days.first.blocks, hasLength(3));
      expect(dto.days.first.blocks[1].type, 'emom');
      expect(dto.days.first.blocks[1].intervalSeconds, 60);
      expect(dto.days.last.blocks[1].workSeconds, 20);
    });

    test('estrae il JSON da un blocco ```json recintato con testo attorno', () {
      final raw =
          'Ecco la scheda digitalizzata:\n```json\n$_validJson\n```\n'
          'Fammi sapere se serve altro!';
      expect(parser.parse(raw).name, 'Upper/Lower — Fase 2');
    });

    test('estrae il primo oggetto bilanciato senza recinzione', () {
      final raw = 'La scheda è questa: $_validJson — spero vada bene';
      expect(parser.parse(raw).name, 'Upper/Lower — Fase 2');
    });

    test('tollera numeri come stringhe e stringhe come numeri', () {
      final dto = parser.parse('''
      {
        "name": "Tolleranza",
        "days": [
          {
            "label": "Unico",
            "blocks": [
              {
                "type": "standard",
                "exercises": [ { "name": "Panca", "sets": "4", "reps": 8 } ]
              }
            ]
          }
        ]
      }
      ''');
      final exercise = dto.days.single.blocks.single.exercises.single;
      expect(exercise.sets, 4);
      expect(exercise.reps, '8');
    });

    test(
      'un esercizio per blocco standard → un blocco solo con tutti dentro',
      () {
        final dto = parser.parse('''
        {
          "name": "Full body",
          "days": [
            {
              "label": "Giorno 1",
              "blocks": [
                {"type": "standard", "exercises": [{"name": "Panca", "sets": 4}]},
                {"type": "standard", "exercises": [{"name": "Croci", "sets": 3}]},
                {"type": "standard", "exercises": [{"name": "Lat machine"}]},
                {"type": "superset", "rounds": 3, "exercises": [{"name": "Curl"}]},
                {"type": "standard", "exercises": [{"name": "Crunch"}]}
              ]
            }
          ]
        }
        ''');

        final blocks = dto.days.single.blocks;
        expect(blocks.map((b) => b.type), ['standard', 'superset', 'standard']);
        expect(
          [for (final e in blocks.first.exercises) e.name],
          ['Panca', 'Croci', 'Lat machine'],
        );
        expect(blocks.first.exercises.first.sets, 4);
      },
    );

    test('rifiuta risposte senza alcun JSON', () {
      expect(
        () => parser.parse('Non riesco a leggere questa immagine.'),
        throwsA(isA<PlanParseException>()),
      );
    });

    test('rifiuta JSON malformato', () {
      expect(
        () => parser.parse('{"name": "Scheda", "days": ['),
        throwsA(isA<PlanParseException>()),
      );
    });

    test('rifiuta tipi di blocco sconosciuti', () {
      expect(
        () => parser.parse(
          '{"name":"S","days":[{"label":"A","blocks":[{"type":"pyramid"}]}]}',
        ),
        throwsA(
          isA<PlanParseException>().having(
            (e) => e.message,
            'message',
            contains('pyramid'),
          ),
        ),
      );
    });

    test(
      'rifiuta EMOM senza intervalSeconds (parametri incoerenti col tipo)',
      () {
        expect(
          () => parser.parse(
            '{"name":"S","days":[{"label":"A","blocks":[{"type":"emom","totalMinutes":10}]}]}',
          ),
          throwsA(
            isA<PlanParseException>().having(
              (e) => e.message,
              'message',
              contains('intervalSeconds'),
            ),
          ),
        );
      },
    );

    test('rifiuta schede senza nome o senza giorni', () {
      expect(
        () => parser.parse('{"days":[{"label":"A","blocks":[]}]}'),
        throwsA(isA<PlanParseException>()),
      );
      expect(
        () => parser.parse('{"name":"S","days":[]}'),
        throwsA(isA<PlanParseException>()),
      );
    });
  });

  // Il flusso "copia e incolla" (RF-03) porta dentro risposte che nessuna API
  // produrrebbe: conversazioni intere, JSON abbelliti, testo tagliato a metà.
  group('PlanParser.parse — risposte incollate a mano', () {
    test('con la conversazione intera vince la risposta, non l\'esempio del '
        'prompt', () {
      final raw =
          '${externalChatPrompt(text: 'Panca 10x4')}\n\n'
          'Certo! Ecco la tua scheda:\n```json\n$_validJson\n```';

      // L'esempio dentro il prompt è una scheda valida a tutti gli effetti:
      // se vincesse lui, l'utente si ritroverebbe in revisione "Nome scheda".
      expect(parser.parse(raw).name, 'Upper/Lower — Fase 2');
    });

    test('tollera le virgole dopo l\'ultimo elemento', () {
      final dto = parser.parse('''
      {
        "name": "Virgole",
        "days": [
          {
            "label": "Unico",
            "blocks": [
              { "type": "standard", "exercises": [ { "name": "Panca", }, ], },
            ],
          },
        ],
      }
      ''');
      expect(dto.days.single.blocks.single.exercises.single.name, 'Panca');
    });

    test('tollera i commenti che qualche modello aggiunge', () {
      final dto = parser.parse('''
      {
        "name": "Commenti", // il nome della scheda
        /* i giorni */
        "days": [
          {
            "label": "Unico",
            "blocks": [{ "type": "standard", "exercises": [{"name": "Squat"}] }]
          }
        ]
      }
      ''');
      expect(dto.name, 'Commenti');
    });

    test(
      'raddrizza le virgolette tipografiche quando sono tutte trasformate',
      () {
        final dto = parser.parse(
          '{“name”: “Virgolette”, “days”: [{“label”: “Unico”, '
          '“blocks”: [{“type”: “standard”, “exercises”: '
          '[{“name”: “Stacco”}]}]}]}',
        );
        expect(dto.name, 'Virgolette');
      },
    );

    test('una nota con le virgolette tipografiche resta intatta', () {
      final dto = parser.parse(
        '{"name": "Note", "days": [{"label": "Unico", "blocks": '
        '[{"type": "standard", "exercises": '
        '[{"name": "Panca", "notes": "presa “stretta”"}]}]}]}',
      );
      expect(
        dto.days.single.blocks.single.exercises.single.notes,
        'presa “stretta”',
      );
    });

    test('dice che la risposta è stata copiata a metà', () {
      expect(
        () => parser.parse(
          'Ecco la scheda:\n```json\n{"name": "Tagliata", "days": [{"label"',
        ),
        throwsA(
          isA<PlanParseException>().having(
            (e) => e.message,
            'message',
            contains('only in part'),
          ),
        ),
      );
    });

    test('scarta gli oggetti JSON che non sono la scheda', () {
      final raw =
          '$_validJson\n\nSe vuoi te la do anche in un altro formato, '
          'tipo {"formato": "csv"}.';
      expect(parser.parse(raw).name, 'Upper/Lower — Fase 2');
    });
  });

  group('PlanParser.fallback', () {
    test('conserva la risposta grezza come blocco freeText (RNF-05)', () {
      const raw = 'testo non strutturabile';
      final dto = parser.fallback(raw);

      expect(dto.name, 'Scheda importata');
      final block = dto.days.single.blocks.single;
      expect(block.type, BlockType.freeText.name);
      expect(block.content, raw);
      expect(parser.validate(dto), isEmpty);
    });
  });

  group('PlanParser.toEntity', () {
    test('mappa la gerarchia completa con sortOrder progressivi', () {
      final plan = parser.toEntity(
        parser.parse(_validJson),
        imagePaths: const ['plan_images/a.jpg'],
      );

      expect(plan.name, 'Upper/Lower — Fase 2');
      expect(plan.imagePaths, ['plan_images/a.jpg']);
      expect(plan.days, hasLength(2));
      expect(plan.days[0].sortOrder, 0);
      expect(plan.days[1].sortOrder, 1);

      final blocks = plan.days.first.blocks;
      expect(blocks.map((b) => b.sortOrder), [0, 1, 2]);
      expect(blocks[0].type, BlockType.standard);
      expect(blocks[1].type, BlockType.emom);
      expect(blocks[1].intervalSeconds, 60);
      expect(blocks[1].totalMinutes, 10);
      expect(blocks[2].type, BlockType.freeText);
      expect(blocks[2].freeTextContent, "Finisher a scelta: 5' corda");

      final bench = blocks.first.exercises.first;
      expect(bench.name, 'Panca piana');
      expect(bench.sets, 4);
      expect(bench.reps, '6-8');
      expect(bench.load, '80kg');
      expect(bench.restSeconds, 150);
      expect(blocks.first.exercises[1].sortOrder, 1);
    });

    test('copia solo i parametri pertinenti al tipo di blocco', () {
      final dto = parser.parse(
        '{"name":"S","days":[{"label":"A","blocks":['
        '{"type":"standard","rounds":5,"durationSeconds":900}'
        ']}]}',
      );
      final block = dto.days.single.blocks.single;
      expect(block.rounds, 5); // il DTO conserva ciò che è arrivato...

      final entity = parser.toEntity(dto).days.single.blocks.single;
      expect(entity.rounds, isNull); // ...ma l'entity standard resta pulita.
      expect(entity.durationSeconds, isNull);
    });

    test('il superset conserva giri e recupero fra i giri', () {
      // "Curl EZ 10 ss French press 10 x4 1'": i giri e il minuto di recupero
      // valgono per la coppia e stanno sul blocco.
      final dto = parser.parse(
        '{"name":"S","days":[{"label":"A","blocks":['
        '{"type":"superset","rounds":4,"restBetweenRoundsSeconds":60,'
        '"exercises":[{"name":"Curl EZ","reps":"10"},'
        '{"name":"French press","reps":"10"}]}'
        ']}]}',
      );

      final block = parser.toEntity(dto).days.single.blocks.single;
      expect(block.type, BlockType.superset);
      expect(block.rounds, 4);
      expect(block.restBetweenRoundsSeconds, 60);
      expect(block.exercises.map((e) => e.sets), [isNull, isNull]);
    });

    test('assegna un\'etichetta di default ai giorni senza label', () {
      final dto = parser.parse(
        '{"name":"S","days":[{"blocks":[{"type":"standard"}]}]}',
      );
      expect(parser.toEntity(dto).days.single.label, 'Giorno 1');
    });
  });
}
