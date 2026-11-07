import '../../core/extensions/blank_text.dart';
import 'dto/plan_dto.dart';

/// Fonde le estrazioni delle singole pagine in una scheda sola.
///
/// Con più immagini ogni pagina viene estratta in una richiesta separata
/// (output molto più corto per chiamata, quindi niente risposte troncate):
/// qui le parti tornano un piano unico. I giorni con la stessa etichetta —
/// un giorno che prosegue sulla pagina dopo — si fondono concatenando i
/// blocchi nell'ordine delle pagine, gli altri restano distinti.
PlanDto mergePlanDtos(List<PlanDto> parts) {
  if (parts.isEmpty) return const PlanDto();
  if (parts.length == 1) return parts.first;

  final days = <String, DayDto>{};
  final order = <String>[];
  for (final part in parts) {
    for (final day in part.days) {
      final key = _dayKey(day.label);
      final existing = days[key];
      if (existing == null) {
        days[key] = day;
        order.add(key);
      } else {
        days[key] = existing.copyWith(
          blocks: [...existing.blocks, ...day.blocks],
          notes: existing.notes ?? day.notes,
        );
      }
    }
  }

  return PlanDto(
    name: _firstNonEmpty(parts.map((p) => p.name)),
    description: _firstNonEmpty(parts.map((p) => p.description)),
    notes: _firstNonEmpty(parts.map((p) => p.notes)),
    days: [for (final key in order) days[key]!],
  );
}

/// Etichette che differiscono solo per maiuscole, spazi o separatori
/// (trattini, due punti, punti) sono lo stesso giorno: "DAY 1 - Petto" e
/// "Day 1 – Petto" si fondono, come "Day 1" e "day 1 ".
String _dayKey(String? label) =>
    (label ?? '').toLowerCase().replaceAll(_separators, ' ').trim();

final _separators = RegExp(r'[\s\-–—:.]+');

String? _firstNonEmpty(Iterable<String?> values) =>
    values.where((value) => !value.isBlank).firstOrNull;
