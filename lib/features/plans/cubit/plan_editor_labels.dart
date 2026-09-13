import '../../../l10n/app_localizations.dart';

/// Le stringhe tradotte di cui [PlanEditorCubit] ha bisogno.
///
/// Il cubit non ha un `BuildContext`, e due di queste etichette non sono
/// nemmeno testo a schermo: l'etichetta di un giorno viene **scritta dentro la
/// scheda** e resta lì anche dopo, quindi va composta nella lingua di chi crea
/// la scheda e non ricalcolata a ogni apertura. Come per `LiveSessionLabels`,
/// le passa chi il contesto ce l'ha, cioè il router.
class PlanEditorLabels {
  const PlanEditorLabels({
    required this.singleDay,
    required this.dayName,
    required this.planNotFound,
    required this.nameRequired,
  });

  /// Costruisce le etichette dalla lingua corrente.
  factory PlanEditorLabels.of(AppLocalizations l10n) => PlanEditorLabels(
    singleDay: l10n.planEditorSingleDayLabel,
    dayName: l10n.planEditorDayName,
    planNotFound: l10n.planEditorPlanNotFound,
    nameRequired: l10n.planEditorNameRequired,
  );

  /// Nome del giorno implicito di una scheda a giorno singolo.
  final String singleDay;

  /// Nome di un giorno appena aggiunto, data la sua lettera (A, B, C…).
  final String Function(String letter) dayName;

  /// Errore mostrato quando l'editor si apre su una scheda non più esistente.
  final String planNotFound;

  /// Errore di validazione mostrato salvando senza nome.
  final String nameRequired;
}
