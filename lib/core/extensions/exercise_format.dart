import '../../data/entities/exercise.dart';
import '../../l10n/app_localizations.dart';

/// Resa testuale della prescrizione di un esercizio, condivisa fra dettaglio
/// scheda (e la sua immagine condivisa) e sessione: è la stessa informazione,
/// e deve leggersi allo stesso modo in tutte e due.
extension ExerciseFormat on Exercise {
  /// Il volume: `3×8`, le sole ripetizioni se le serie non ci sono, vuoto se
  /// mancano entrambe.
  String get volume => sets != null ? '$sets×${reps ?? '?'}' : (reps ?? '');

  /// Il resto della prescrizione, nell'ordine in cui si legge: carico,
  /// recupero, durata. Le parti assenti non compaiono.
  List<String> prescriptionDetails(AppLocalizations l10n) => [
    if ((load ?? '').isNotEmpty) load!,
    if (restSeconds case final seconds?) l10n.planDetailExerciseRest(seconds),
    if (durationSeconds case final seconds?)
      l10n.planDetailExerciseDuration(seconds),
  ];

  /// La prescrizione intera su una riga: `3×8 · 70% 1RM · Recupero 90s`.
  String prescription(AppLocalizations l10n) =>
      [if (volume.isNotEmpty) volume, ...prescriptionDetails(l10n)].join(' · ');
}
