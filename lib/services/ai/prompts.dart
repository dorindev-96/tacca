/// System prompt e schema JSON delle chiamate AI (§6.3).
///
/// Centralizzati qui: provider e parser non contengono testo di prompt.
library;

/// Fase 1 dell'import da foto: trascrizione, senza structured output.
///
/// Chiedere lettura e strutturazione nella stessa risposta si è rivelato
/// fragile: sotto la grammatica del `json_schema` il modello degenera (loop di
/// cifre dentro un intero) e la scheda arriva amputata. Qui non c'è schema, il
/// compito è solo copiare — e la trascrizione resta il contenuto migliore da
/// conservare se poi la strutturazione fallisce (RNF-05).
const transcriptionSystemPrompt = '''
You are an expert transcriber of gym workout plans.
You receive a photo of a plan and write out everything it says, as text.

Binding rules:
- Transcribe EVERY line you can see, top to bottom, in the order of the
  original: titles, day names, every exercise line with its numbers, notes in
  the margin. Do not skip lines, do not summarise, do not reorder.
- Write the plan in ITS OWN LANGUAGE, exactly as printed. These instructions
  are in English, the plan almost certainly is not: never translate it.
- Copy numbers exactly as written (10x4, 10-10x4, 1'30", 5', 70% 1RM): do not
  convert them and do not interpret them.
- One transcribed line per line of the plan.
- If a word is illegible write [?] in its place: invent nothing.
- Reply with the text of the plan only: no commentary, no JSON.
''';

/// Le regole di merito dell'estrazione (§6.3): non inventare, non scartare,
/// mantenere la lingua della scheda, raggruppare in blocchi.
///
/// Stanno qui da sole perché non dipendono da *come* si parla al modello:
/// valgono identiche per la chiamata via API ([extractionSystemPrompt]) e per
/// il prompt che l'utente copia in una chat qualsiasi ([externalChatPrompt]).
/// Quello che cambia fra i due è solo la forma della risposta attesa.
const _extractionRules = r'''
- Do not invent exercises, sets, loads or values that are absent from the
  original: fields that are not there stay null or are omitted.
- Any content you cannot interpret in a structured way must be kept verbatim
  in a {"type": "freeText", "content": "..."} block: never discard content.
- Times in seconds in the *Seconds fields; "reps" and "load" are free strings
  (e.g. "8-12", "max", "70% 1RM", "bodyweight").

Language of the answer (read this twice):
- These instructions are in English. THE PLAN IS NOT, and the JSON you produce
  must stay in the language of the plan you were given.
- Copy across in the original language, character for character where you can:
  exercise names, day labels, the plan name, section headings, and every note.
  "Panca piana" stays "Panca piana"; "Knäböj" stays "Knäböj". Translating them
  into English is a mistake, even though we are speaking English here.
- Only the JSON field names are English, because they are part of the format:
  "name", "days", "blocks", "exercises", "reps" and the rest.

Completeness (the most important rule):
- Convert ALL the text you received, line by line, in the order it appears:
  every day and every exercise of each day. Do not summarise, do not stop
  after the first few exercises, do not merge different lines.
- Every exercise line in the text must produce one exercise in the JSON.
- Before answering, check again that you have as many entries as there are
  exercise lines in the text.
- Numbers are small and realistic: "sets" and "rounds" stay under 100, the
  *Seconds fields under 3600. Never repeat a digit to fill a field.

Notation that recurs in workout plans (the words around the numbers change
with the language, the numbers do not):
- "10x4" = 10 reps for 4 sets -> "reps": "10", "sets": 4.
- "10-10x4" = 10 reps per side, 4 sets -> "reps": "10+10", "sets": 4.
- The time after the sets is the rest: 1'30" -> "restSeconds": 90, 30" -> 30.
- A machine or a stretch with only a time next to it ("5' treadmill",
  "Stretching 10'") is a duration exercise -> "durationSeconds": 300 / 600,
  with no sets and no reps.
- A superset is written with a joining word between two exercises on the same
  line: "ss", "superserie" (it), "+", "superset", "SS". Produce one "superset"
  block holding both exercises. The sets and the rest written at the end of
  the line belong to the pair, not to the second exercise: "Curl EZ 10 ss
  French press 10 x4 1'" -> a "superset" block with "rounds": 4 and
  "restBetweenRoundsSeconds": 60, holding two exercises with "reps": "10" and
  no "sets".

Grouping into blocks (the most frequent mistake, read carefully):
- A block is NOT a line of the plan: it is the GROUP of exercises performed
  together or one after the other. The default container is "standard".
- All consecutive classic exercises — each with its own sets, reps and rest —
  go in the SAME "standard" block, as successive objects inside "exercises",
  in the order of the plan.
- A day with 5 classic exercises = 1 "standard" block with 5 objects in
  "exercises". WRONG: 5 "standard" blocks with one exercise each.
- Open a new "standard" block only where the plan marks a change of section
  (e.g. "warm-up", "main part", "cool-down", "core", in whatever language the
  plan uses): the section heading goes in the block's "notes".
- Open a block of a type other than "standard" only where the plan explicitly
  states that way of training (superset, circuit, EMOM, AMRAP, Tabata, for
  time).
- The block's "notes" describes the group; anything about a single exercise
  goes in that exercise's "notes", never in the block's.
- The number of blocks in a day is almost always 1 or 2, rarely more than 4.
  If you end up with as many blocks as there are exercises, you got it wrong:
  merge them into one.

Block types and allowed parameters (ONLY these eight, do not invent others):
- "standard": no parameters — exercises performed one after the other
- "superset": rounds, restBetweenRoundsSeconds — two or more exercises
  alternated with no rest in between, resting at the end of each round
- "circuit": rounds, restBetweenRoundsSeconds
- "emom": intervalSeconds, totalMinutes
- "amrap": durationSeconds
- "tabata": workSeconds, restSeconds, rounds
- "forTime": timeCapSeconds (optional)
- "freeText": content
A duration-only exercise (treadmill, bike, stretching) is NOT a block type of
its own and does not deserve a block to itself: it is an ordinary exercise
with "durationSeconds" set and no "reps"/"sets", inside the "standard" block
where it appears (usually the warm-up one).

Allowed fields (use no others, do not rename them):
- plan: "name" (required), "description", "notes", "days" (required)
- day: "label" (required), "notes", "blocks"
- block: "type" (required), "notes", "exercises", plus the parameters of its
  own type listed above
- exercise: "name" (required), "sets" (integer), "reps" (string),
  "load" (string), "restSeconds", "durationSeconds", "notes"

Exact shape of the JSON (the field names are binding, use no others: no "day"
instead of "label", no flat "exercise" field on blocks — every exercise is an
object inside the "exercises" array with a "name" property). Note how the four
consecutive exercises sit in a single block, and how the content stays in the
language of the plan while the field names stay English:
```json
{
  "name": "Nome scheda",
  "days": [
    {
      "label": "Giorno 1",
      "blocks": [
        {
          "type": "standard",
          "notes": "Riscaldamento",
          "exercises": [{"name": "Tapis roulant", "durationSeconds": 300}]
        },
        {
          "type": "standard",
          "exercises": [
            {"name": "Panca piana", "reps": "10", "sets": 4, "restSeconds": 90},
            {"name": "Croci ai cavi", "reps": "12", "sets": 3, "restSeconds": 60},
            {"name": "Lat machine", "reps": "10+10", "sets": 4, "restSeconds": 90},
            {"name": "Pulley", "reps": "12", "sets": 3, "load": "40kg",
             "notes": "presa stretta"}
          ]
        },
        {
          "type": "superset",
          "rounds": 4,
          "exercises": [
            {"name": "Curl bicipiti", "reps": "10"},
            {"name": "French press", "reps": "10"}
          ],
          "restBetweenRoundsSeconds": 60
        }
      ]
    }
  ]
}
```
''';

/// System prompt della strutturazione via API (§6.3).
///
/// Le regole di merito sono quelle condivise; qui davanti c'è solo il patto
/// sulla forma della risposta, scritto per un'API che espone lo structured
/// output (e per il fallback prompt-based di chi lo rifiuta).
const extractionSystemPrompt = '''
You are an assistant that digitises gym workout plans.
You receive the text of a plan — often the transcription of a photo — and you
return that plan as JSON conforming to the schema you were given.

Binding rules:
- Reply with a valid JSON object conforming to the schema ONLY, with no text
  before or after it. If you cannot use structured output, wrap the JSON in a
  ```json block.
$_extractionRules''';

/// Il messaggio che l'utente copia negli appunti e incolla nella chat AI che
/// preferisce (RF-03, modalità senza API key).
///
/// Deve bastare a sé stesso: nessuno schema allegato alla richiesta, nessun
/// structured output, nessun secondo turno automatico. Perciò si porta dentro
/// le stesse regole dell'estrazione via API, l'elenco dei campi ammessi e —
/// in fondo — il testo della scheda, delimitato da righe riconoscibili
/// perché il modello non lo confonda con le istruzioni.
///
/// Le tre regole in cima sono quelle che rendono la risposta *incollabile*:
/// un solo blocco recintato (il [PlanParser] lo preferisce a tutto il resto),
/// niente virgole pendenti o commenti (le due malformazioni che una chat
/// produce davvero) e il divieto di fermarsi a metà, che è il modo in cui le
/// schede lunghe arrivano tronche.
String externalChatPrompt({required String text, String? userHint}) {
  final buffer = StringBuffer()
    ..writeln('You are an assistant that digitises gym workout plans.')
    ..writeln(
      'At the bottom of this message, after the "=== WORKOUT PLAN ===" line, '
      'you will find',
    )
    ..writeln('the text of a workout plan: convert it into JSON.')
    ..writeln()
    ..writeln('How to answer (an application reads your reply, not a person):')
    ..writeln(
      '- Reply with ONE SINGLE ```json block and nothing else: no greeting, '
      'no',
    )
    ..writeln('  explanation before or after, no questions.')
    ..writeln(
      '- Inside the block, one single valid JSON object: straight quotes ("),',
    )
    ..writeln(
      '  no comments, no trailing comma after the last element of an object '
      'or of',
    )
    ..writeln('  an array.')
    ..writeln(
      '- Do not cut the answer short: if the plan is long, write it out in '
      'full',
    )
    ..writeln('  anyway.')
    ..writeln()
    ..writeln('Binding rules:')
    ..writeln(_extractionRules)
    ..writeln('=== WORKOUT PLAN ===')
    ..writeln(text.trim())
    ..writeln('=== END OF WORKOUT PLAN ===');
  if (userHint != null && userHint.trim().isNotEmpty) {
    buffer
      ..writeln()
      ..writeln(
        'Notes from the person writing to you (they may be in another '
        'language):',
      )
      ..writeln(userHint.trim());
  }
  return buffer.toString().trim();
}

/// Il messaggio correttivo da rimandare nella stessa chat quando la risposta
/// incollata non è utilizzabile: è il [retryUserText] del retry automatico,
/// detto a una chat invece che a un'API.
///
/// Senza key non c'è nessun retry che possiamo fare noi, ma l'errore di
/// parsing resta l'informazione che fa correggere il modello: gliela facciamo
/// arrivare per le mani dell'utente.
String externalChatCorrection(String parseError) {
  return 'The previous answer cannot be used. Error: $parseError\n'
      'Answer again with the corrected, complete ```json block only, with no '
      'text before or after it, keeping the plan in its original language.';
}

/// Schema della scheda (§5.3), usato come structured output dai modelli che
/// lo supportano (`response_format: json_schema` su OpenRouter,
/// `output_config.format` su Anthropic, che però non accetta i vincoli
/// numerici e li fa togliere al provider, `generationConfig.responseSchema`
/// su Google, che è OpenAPI e non JSON Schema e se lo fa tradurre).
const Map<String, dynamic> planJsonSchema = {
  'type': 'object',
  'additionalProperties': false,
  'required': ['name', 'days'],
  'properties': {
    'name': {'type': 'string'},
    'description': {
      'type': ['string', 'null'],
    },
    'notes': {
      'type': ['string', 'null'],
    },
    'days': {
      'type': 'array',
      'minItems': 1,
      'items': {
        'type': 'object',
        'additionalProperties': false,
        'required': ['label', 'blocks'],
        'properties': {
          'label': {'type': 'string'},
          'notes': {
            'type': ['string', 'null'],
          },
          'blocks': {
            'type': 'array',
            'description':
                'Groups of exercises for the day, not lines of the plan. '
                'Consecutive classic exercises all sit in a single "standard" '
                'block: a day normally has 1 or 2 blocks, never one per '
                'exercise.',
            'items': {
              'type': 'object',
              'additionalProperties': false,
              'required': ['type'],
              'properties': {
                'type': {
                  'type': 'string',
                  'description':
                      'How the group is performed. "standard" (default) for '
                      'exercises done one after the other; the other types '
                      'only where the plan states them explicitly.',
                  'enum': [
                    'standard',
                    'superset',
                    'circuit',
                    'emom',
                    'amrap',
                    'tabata',
                    'forTime',
                    'freeText',
                  ],
                },
                'notes': {
                  'type': ['string', 'null'],
                  'description':
                      'A note covering the whole group (e.g. a section '
                      'heading), in the language of the plan. Anything about '
                      'a single exercise goes in that exercise\'s "notes".',
                },
                'intervalSeconds': {
                  'type': ['integer', 'null'],
                },
                'totalMinutes': {
                  'type': ['integer', 'null'],
                },
                'durationSeconds': {
                  'type': ['integer', 'null'],
                },
                'workSeconds': {
                  'type': ['integer', 'null'],
                },
                'restSeconds': {
                  'type': ['integer', 'null'],
                },
                'rounds': {
                  'type': ['integer', 'null'],
                },
                'restBetweenRoundsSeconds': {
                  'type': ['integer', 'null'],
                },
                'timeCapSeconds': {
                  'type': ['integer', 'null'],
                },
                'content': {
                  'type': ['string', 'null'],
                },
                'exercises': {
                  'type': 'array',
                  'description':
                      'Every exercise of the group, in the order of the '
                      'plan: one entry per exercise line, named in the '
                      'language of the plan.',
                  'items': {
                    'type': 'object',
                    'additionalProperties': false,
                    'required': ['name'],
                    'properties': {
                      'name': {'type': 'string'},
                      'sets': {
                        'type': ['integer', 'null'],
                      },
                      'reps': {
                        'type': ['string', 'null'],
                      },
                      'load': {
                        'type': ['string', 'null'],
                      },
                      'restSeconds': {
                        'type': ['integer', 'null'],
                      },
                      'durationSeconds': {
                        'type': ['integer', 'null'],
                      },
                      'notes': {
                        'type': ['string', 'null'],
                      },
                    },
                  },
                },
              },
            },
          },
        },
      },
    },
  },
};

/// Testo del messaggio utente della fase di trascrizione.
///
/// Ogni immagine viaggia in una richiesta separata: [pageIndex] e [pageCount]
/// dicono al modello che sta guardando una parte della scheda, così non prova
/// a ricostruire (o riassumere) quello che non vede.
String transcriptionUserText({int? pageIndex, int? pageCount}) {
  if (pageIndex != null && pageCount != null && pageCount > 1) {
    return 'This is page $pageIndex of $pageCount of the same workout plan. '
        'Transcribe in full only what you see in this image, line by line, '
        'without adding the other pages. Keep the original language.';
  }
  return 'Transcribe in full the workout plan in this image, line by line, '
      'keeping the original language.';
}

/// Testo del messaggio utente per la strutturazione in JSON.
///
/// [text] è la trascrizione della pagina (o il testo incollato dall'utente);
/// [pageIndex] e [pageCount] restano per dire al modello che sta guardando
/// una parte della scheda e non deve inventare il resto.
String extractionUserText({
  String? text,
  String? userHint,
  int? pageIndex,
  int? pageCount,
}) {
  final buffer = StringBuffer();
  if (pageIndex != null && pageCount != null && pageCount > 1) {
    buffer.writeln(
      'This is the text of page $pageIndex of $pageCount of the same plan. '
      'Convert only what you read here: if the page starts halfway through a '
      'day, use that day\'s heading as the "label", exactly as it appears.',
    );
  }
  if (text != null && text.trim().isNotEmpty) {
    buffer
      ..writeln('Workout plan to convert into JSON:')
      ..writeln(text.trim());
  }
  if (userHint != null && userHint.trim().isNotEmpty) {
    buffer
      ..writeln('Notes from the user (they may be in another language):')
      ..writeln(userHint.trim());
  }
  return buffer.toString().trim();
}

/// Messaggio correttivo del retry automatico (§6.2, punto 4): l'errore di
/// parsing torna al modello come istruzione.
String retryUserText(String parseError) {
  return 'The previous answer was not valid JSON conforming to the schema. '
      'Error: $parseError\n'
      'Answer again with the corrected JSON object ONLY, with no text before '
      'or after it, keeping the plan in its original language.';
}
