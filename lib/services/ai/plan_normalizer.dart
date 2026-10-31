import '../../core/extensions/blank_text.dart';
import '../../data/entities/block.dart';
import 'dto/plan_dto.dart';

/// Normalizza la *forma* della scheda proposta dall'AI, prima che diventi
/// entity (§6.2).
///
/// I modelli traducono la scheda riga per riga, e una riga diventa un blocco:
/// cinque esercizi classici arrivano come cinque blocchi `standard` da un
/// esercizio ciascuno. Nel modello dati (§4.1) il blocco è il *raggruppamento*
/// — ciò che si esegue insieme — quindi la forma corretta è un blocco
/// `standard` con cinque esercizi dentro. Il prompt lo chiede esplicitamente,
/// ma nessun prompt lo garantisce: qui la risposta viene resa canonica
/// comunque, così la scheda in editor (e nella sessione) è la stessa
/// qualunque modello l'abbia prodotta.
///
/// Due sole regole, applicate a ogni giorno:
/// 1. una nota di blocco su un `standard` con un solo esercizio è in realtà
///    la nota di quell'esercizio, e scende su di lui;
/// 2. un blocco `standard` senza note proprie confluisce nel blocco
///    `standard` che lo precede, accodandone gli esercizi.
///
/// Restano quindi distinti i blocchi `standard` con una nota propria — la
/// scheda segnalava una sezione ("Riscaldamento", "Defaticamento") — e tutti
/// i blocchi degli altri tipi, che descrivono una modalità di esecuzione e
/// non vanno mai fusi. L'ordine non cambia mai.
PlanDto normalizePlanDto(PlanDto dto) {
  return dto.copyWith(
    days: [
      for (final day in dto.days)
        day.copyWith(blocks: normalizeBlocks(day.blocks)),
    ],
  );
}

/// Applica le due regole di [normalizePlanDto] ai blocchi di un giorno.
List<BlockDto> normalizeBlocks(List<BlockDto> blocks) {
  final result = <BlockDto>[];
  for (final raw in blocks) {
    final block = _demoteSoleExerciseNote(raw);
    final previous = result.isEmpty ? null : result.last;
    if (previous != null && _isStandard(previous) && _isAbsorbable(block)) {
      result[result.length - 1] = previous.copyWith(
        exercises: [...previous.exercises, ...block.exercises],
      );
      continue;
    }
    result.add(block);
  }
  return result;
}

/// Su un `standard` con un solo esercizio, nota del blocco e nota
/// dell'esercizio dicono la stessa cosa: farla scendere sull'esercizio la
/// tiene attaccata al suo contenuto anche dopo il raggruppamento. Se
/// l'esercizio ha già una nota propria non si sovrascrive nulla e il blocco
/// resta a sé.
BlockDto _demoteSoleExerciseNote(BlockDto block) {
  if (!_isStandard(block) || block.notes.isBlank) return block;
  if (block.exercises.length != 1) return block;
  final exercise = block.exercises.single;
  if (!exercise.notes.isBlank) return block;
  return block.copyWith(
    notes: null,
    exercises: [exercise.copyWith(notes: block.notes)],
  );
}

/// Un blocco confluisce nel precedente solo se è `standard` e non porta una
/// nota di gruppo: la nota è il segno che la scheda apriva lì una sezione.
bool _isAbsorbable(BlockDto block) => _isStandard(block) && block.notes.isBlank;

bool _isStandard(BlockDto block) => block.type == BlockType.standard.name;
