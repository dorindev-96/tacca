import 'dart:convert';

import '../../core/errors/app_exception.dart';
import '../../data/entities/block.dart';
import '../../data/entities/exercise.dart';
import '../../data/entities/workout_day.dart';
import '../../data/entities/workout_plan.dart';
import 'dto/plan_dto.dart';
import 'plan_normalizer.dart';

/// Risposta AI non trasformabile in una [PlanDto] valida. Il messaggio è
/// pensato per essere rimandato al modello nel retry correttivo (§6.2).
class PlanParseException extends AppException {
  const PlanParseException(super.message, {super.cause});
}

/// Pipeline unica di parsing delle risposte AI (§6.2): estrazione del JSON,
/// decodifica in [PlanDto], validazione semantica, normalizzazione della forma
/// e mapping DTO → entity. Tutti i provider passano da qui.
class PlanParser {
  const PlanParser();

  /// Estrae, decodifica, valida e normalizza. Lancia [PlanParseException] con
  /// la lista dei problemi trovati.
  ///
  /// La risposta può contenere più di un candidato — una chat premette un
  /// saluto, mostra un esempio, ripete la richiesta prima del blocco buono —
  /// quindi si provano tutti in ordine di attendibilità e vince il primo che
  /// si decodifica *e* passa la validazione.
  PlanDto parse(String raw) {
    final candidates = _jsonCandidates(raw);
    if (candidates.isEmpty) throw _noJsonFound(raw);

    PlanParseException? decodeError;
    PlanParseException? schemaError;
    for (final candidate in candidates) {
      final Map<String, dynamic> decoded;
      try {
        decoded = _decodeObject(candidate);
      } on PlanParseException catch (e) {
        decodeError ??= e;
        continue;
      }
      try {
        return _toPlanDto(decoded);
      } on PlanParseException catch (e) {
        schemaError ??= e;
      }
    }

    // Fra i due errori vince quello semantico: dice *cosa* sistemare, mentre
    // "JSON malformato" dice solo che non si legge. È il messaggio che torna
    // al modello, nel retry automatico o per le mani dell'utente.
    throw schemaError ?? decodeError!;
  }

  /// Validazione semantica (§6.2 punto 3): tipi di blocco noti, parametri
  /// coerenti col tipo, almeno un giorno. Ritorna i problemi trovati.
  List<String> validate(PlanDto dto) {
    final issues = <String>[];
    if (dto.name == null || dto.name!.trim().isEmpty) {
      issues.add('the "name" field is missing or empty');
    }
    if (dto.days.isEmpty) {
      issues.add('the plan must have at least one day in "days"');
    }
    for (var d = 0; d < dto.days.length; d++) {
      final day = dto.days[d];
      final dayRef = 'day ${d + 1}';
      for (var b = 0; b < day.blocks.length; b++) {
        final block = day.blocks[b];
        final blockRef = '$dayRef, block ${b + 1}';
        final typeName = block.type;
        final type = typeName == null
            ? null
            : BlockType.values.asNameMap()[typeName];
        if (type == null) {
          issues.add('$blockRef: unknown block type "$typeName"');
          continue;
        }
        switch (type) {
          case BlockType.emom:
            if ((block.intervalSeconds ?? 0) <= 0) {
              issues.add('$blockRef: EMOM without "intervalSeconds"');
            }
            if ((block.totalMinutes ?? 0) <= 0) {
              issues.add('$blockRef: EMOM without "totalMinutes"');
            }
          case BlockType.amrap:
            if ((block.durationSeconds ?? 0) <= 0) {
              issues.add('$blockRef: AMRAP without "durationSeconds"');
            }
          case BlockType.tabata:
            if ((block.workSeconds ?? 0) <= 0 ||
                (block.restSeconds ?? 0) <= 0) {
              issues.add(
                '$blockRef: Tabata without "workSeconds"/"restSeconds"',
              );
            }
          case BlockType.freeText:
            if (block.content == null || block.content!.trim().isEmpty) {
              issues.add('$blockRef: freeText block without "content"');
            }
          case BlockType.standard:
          case BlockType.superset:
          case BlockType.circuit:
          case BlockType.forTime:
            break;
        }
        for (var e = 0; e < block.exercises.length; e++) {
          final exercise = block.exercises[e];
          if (exercise.name == null || exercise.name!.trim().isEmpty) {
            issues.add('$blockRef, exercise ${e + 1}: "name" missing');
          }
        }
      }
    }
    return issues;
  }

  /// Fallback dopo il secondo fallimento (§6.2 punto 5, RNF-05): il testo
  /// grezzo della risposta diventa un blocco `freeText` editabile.
  PlanDto fallback(String raw, {String? planName}) {
    return PlanDto(
      name: planName == null || planName.trim().isEmpty
          ? 'Scheda importata'
          : planName.trim(),
      days: [
        DayDto(
          label: 'Giorno unico',
          blocks: [BlockDto(type: BlockType.freeText.name, content: raw)],
        ),
      ],
    );
  }

  /// Unico punto di conversione DTO → entity (§6.2 punto 6). Assegna i
  /// `sortOrder` e copia solo i parametri pertinenti al tipo di blocco.
  WorkoutPlan toEntity(PlanDto dto, {List<String> imagePaths = const []}) {
    final now = DateTime.now();
    final plan = WorkoutPlan(
      name: dto.name?.trim() ?? '',
      description: dto.description,
      notes: dto.notes,
      createdAt: now,
      updatedAt: now,
      imagePaths: List.of(imagePaths),
    );

    for (var d = 0; d < dto.days.length; d++) {
      final dayDto = dto.days[d];
      final day = WorkoutDay(
        label: dayDto.label?.trim().isNotEmpty ?? false
            ? dayDto.label!.trim()
            : 'Giorno ${d + 1}',
        notes: dayDto.notes,
        sortOrder: d,
      );
      for (var b = 0; b < dayDto.blocks.length; b++) {
        final blockDto = dayDto.blocks[b];
        final type =
            BlockType.values.asNameMap()[blockDto.type] ?? BlockType.freeText;
        final block = Block.ofType(type, sortOrder: b, notes: blockDto.notes);
        switch (type) {
          case BlockType.standard:
            break;
          case BlockType.superset:
            // Anche il superset ha un recupero fra un giro e l'altro: era il
            // dato che nella scheda sta in fondo alla riga ("... x4 1'").
            block
              ..rounds = blockDto.rounds
              ..restBetweenRoundsSeconds = blockDto.restBetweenRoundsSeconds;
          case BlockType.circuit:
            block
              ..rounds = blockDto.rounds
              ..restBetweenRoundsSeconds = blockDto.restBetweenRoundsSeconds;
          case BlockType.emom:
            block
              ..intervalSeconds = blockDto.intervalSeconds
              ..totalMinutes = blockDto.totalMinutes;
          case BlockType.amrap:
            block.durationSeconds = blockDto.durationSeconds;
          case BlockType.tabata:
            block
              ..workSeconds = blockDto.workSeconds
              ..restSeconds = blockDto.restSeconds
              ..rounds = blockDto.rounds;
          case BlockType.forTime:
            block.timeCapSeconds = blockDto.timeCapSeconds;
          case BlockType.freeText:
            block.freeTextContent = blockDto.content ?? '';
        }
        for (var e = 0; e < blockDto.exercises.length; e++) {
          final exerciseDto = blockDto.exercises[e];
          block.exercises.add(
            Exercise(
              name: exerciseDto.name?.trim() ?? '',
              sets: exerciseDto.sets,
              reps: exerciseDto.reps,
              load: exerciseDto.load,
              restSeconds: exerciseDto.restSeconds,
              durationSeconds: exerciseDto.durationSeconds,
              notes: exerciseDto.notes,
              sortOrder: e,
            ),
          );
        }
        day.blocks.add(block);
      }
      plan.days.add(day);
    }
    return plan;
  }

  /// Decodifica in [PlanDto], valida e normalizza un oggetto già letto.
  PlanDto _toPlanDto(Map<String, dynamic> decoded) {
    final PlanDto dto;
    try {
      dto = PlanDto.fromJson(decoded);
    } catch (e) {
      throw PlanParseException(
        'JSON does not conform to the plan schema: $e',
        cause: e,
      );
    }

    // Validazione sulla risposta così com'è: i riferimenti nei messaggi
    // d'errore ("day 2, block 3") devono corrispondere a ciò che il
    // modello ha scritto, perché è a lui che tornano nel retry.
    final issues = validate(dto);
    if (issues.isNotEmpty) {
      throw PlanParseException('Invalid plan: ${issues.join('; ')}.');
    }
    return normalizePlanDto(dto);
  }

  /// "Non ho trovato JSON" e "il JSON finisce a metà" sono due problemi
  /// diversi per chi incolla a mano una risposta: il secondo si risolve
  /// tornando nella chat a copiare tutto, e va detto.
  PlanParseException _noJsonFound(String raw) {
    return raw.contains('{')
        ? const PlanParseException(
            'The JSON is incomplete: the closing brace is missing. The '
            'answer was probably copied only in part.',
          )
        : const PlanParseException('No JSON object found in the answer.');
  }

  /// I possibili oggetti JSON dentro [raw], in ordine di attendibilità:
  /// prima quelli dentro i blocchi recintati ```…``` (è lì che una chat mette
  /// il risultato), poi ogni oggetto `{…}` bilanciato del testo grezzo.
  ///
  /// **Dall'ultimo al primo**, in entrambi i passaggi. Chi incolla a mano
  /// spesso porta con sé l'intera conversazione, e il prompt che abbiamo
  /// fatto copiare contiene un esempio di scheda completo e valido: preso in
  /// ordine di lettura vincerebbe l'esempio, e l'utente si ritroverebbe in
  /// revisione una scheda che non è la sua. La risposta, in una
  /// conversazione, viene dopo la domanda.
  List<String> _jsonCandidates(String raw) {
    final candidates = <String>[];
    void collect(Iterable<String> found) {
      for (final object in found.toList().reversed) {
        if (!candidates.contains(object)) candidates.add(object);
      }
    }

    for (final match in _fencedBlock.allMatches(raw).toList().reversed) {
      collect(_balancedObjects(match.group(1)!));
    }
    collect(_balancedObjects(raw));
    return candidates;
  }

  /// Tutti gli oggetti `{…}` bilanciati di primo livello, nell'ordine in cui
  /// compaiono. Una graffa che non si chiude non ferma la ricerca: si
  /// riparte dalla successiva, altrimenti una parentesi lasciata nel discorso
  /// nasconderebbe il JSON che viene dopo.
  List<String> _balancedObjects(String source) {
    final objects = <String>[];
    var from = 0;
    while (true) {
      final start = source.indexOf('{', from);
      if (start < 0) return objects;
      final end = _matchingBrace(source, start);
      if (end < 0) {
        from = start + 1;
        continue;
      }
      objects.add(source.substring(start, end + 1));
      from = end + 1;
    }
  }

  /// Indice della graffa che chiude quella in [start], -1 se non si chiude.
  int _matchingBrace(String source, int start) {
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = start; i < source.length; i++) {
      final char = source[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (char == r'\') {
        escaped = true;
        continue;
      }
      if (char == '"') inString = !inString;
      if (inString) continue;
      if (char == '{') depth++;
      if (char == '}') {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
  }

  /// Decodifica un candidato, riprovando con le riparazioni che servono a un
  /// JSON arrivato per gli appunti invece che da un'API.
  Map<String, dynamic> _decodeObject(String candidate) {
    FormatException? failure;
    for (final attempt in _decodeAttempts(candidate)) {
      final Object? decoded;
      try {
        decoded = jsonDecode(attempt);
      } on FormatException catch (e) {
        failure ??= e;
        continue;
      }
      if (decoded is! Map<String, dynamic>) {
        throw const PlanParseException(
          'The decoded JSON is not a plan object.',
        );
      }
      return decoded;
    }
    throw PlanParseException(
      'Malformed JSON: ${failure!.message}',
      cause: failure,
    );
  }

  /// Il testo così com'è per primo — un JSON valido non va mai toccato — e
  /// solo dopo le varianti riparate.
  List<String> _decodeAttempts(String candidate) {
    final attempts = <String>[candidate];
    void add(String value) {
      if (!attempts.contains(value)) attempts.add(value);
    }

    add(_repairJson(candidate));
    final straight = _straightenQuotes(candidate);
    if (straight != candidate) {
      add(straight);
      add(_repairJson(straight));
    }
    return attempts;
  }

  /// Toglie le due malformazioni che i modelli producono davvero: i commenti
  /// (`//`, `/* */`, che JSON non ammette) e la virgola dopo l'ultimo
  /// elemento. Lavora consapevole delle stringhe, così un `//` dentro una
  /// nota o una virgola dentro un testo restano dove sono.
  String _repairJson(String source) {
    final out = <String>[];
    var inString = false;
    var escaped = false;
    for (var i = 0; i < source.length; i++) {
      final char = source[i];
      if (inString) {
        out.add(char);
        if (escaped) {
          escaped = false;
        } else if (char == r'\') {
          escaped = true;
        } else if (char == '"') {
          inString = false;
        }
        continue;
      }
      if (char == '"') {
        inString = true;
        out.add(char);
        continue;
      }
      if (char == '/' && i + 1 < source.length) {
        final next = source[i + 1];
        if (next == '/') {
          var end = i + 2;
          while (end < source.length && source[end] != '\n') {
            end++;
          }
          i = end - 1;
          continue;
        }
        if (next == '*') {
          final end = source.indexOf('*/', i + 2);
          i = end < 0 ? source.length : end + 1;
          continue;
        }
      }
      if (char == '}' || char == ']') {
        var last = out.length - 1;
        while (last >= 0 && out[last].trim().isEmpty) {
          last--;
        }
        if (last >= 0 && out[last] == ',') out.removeAt(last);
      }
      out.add(char);
    }
    return out.join();
  }

  /// Raddrizza le virgolette tipografiche, ma **solo** se nel candidato non
  /// ce n'è nemmeno una dritta: vuol dire che qualcosa lungo la strada le ha
  /// trasformate tutte. Farlo su un JSON già valido rovinerebbe la nota che
  /// le contiene per davvero.
  String _straightenQuotes(String source) {
    if (source.contains('"')) return source;
    return source.replaceAll(_typographicQuotes, '"');
  }
}

/// Un blocco recintato con il suo eventuale linguaggio (```json, ```JSON, ```).
final _fencedBlock = RegExp(r'```[a-zA-Z]*[ \t]*\n?([\s\S]*?)```');

final _typographicQuotes = RegExp('[“”„‟″]');
