import '../../data/entities/log_set.dart';
import 'blank_text.dart';

/// Resa testuale di una serie registrata, condivisa fra sessione e storico.
///
/// Le entity ObjectBox sono il modello di dominio (ADR-01): l'estensione vive
/// qui perché il formato è identico ovunque compaia una serie.
extension LogSetFormat on LogSet {
  /// `80 kg × 8`; le parti non registrate vengono omesse, una serie spuntata
  /// senza valori resta comunque visibile come `✓`.
  String get summary {
    final parts = <String>[
      if (weightKg case final value?) '${formatWeightKg(value)} kg',
      if (reps.trimmedOrNull case final value?) value,
    ];
    return parts.isEmpty ? '✓' : parts.join(' × ');
  }
}

/// Le serie di un esercizio in una riga: `80 kg × 8 · 80 kg × 6`.
extension LogSetsFormat on Iterable<LogSet> {
  String get summary => map((set) => set.summary).join(' · ');
}

/// Carico senza decimali inutili: in palestra i pesi sono interi o mezzi kg.
String formatWeightKg(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(1);
