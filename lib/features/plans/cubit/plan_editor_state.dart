import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../data/entities/workout_plan.dart';

part 'plan_editor_state.freezed.dart';

/// Perché l'editor non è andato avanti: alla pagina serve solo per scegliere
/// il messaggio.
enum PlanEditorFailure {
  /// La scheda da modificare non esiste (più).
  notFound,

  /// Salvataggio senza nome.
  nameRequired,

  /// Il database non ha accettato il salvataggio.
  saveFailed,
}

/// Stato dell'editor manuale (RF-02).
///
/// [draft] è l'entity ObjectBox in editing: un POJO mutabile (ADR-01,
/// nessun domain layer separato). Il [PlanEditorCubit] la muta in place e
/// incrementa [revision] ad ogni cambiamento, perché l'uguaglianza generata
/// da freezed non "vedrebbe" altrimenti una mutazione interna allo stesso
/// oggetto — [revision] è il segnale esplicito che forza il rebuild.
@freezed
sealed class PlanEditorState with _$PlanEditorState {
  const PlanEditorState._();

  const factory PlanEditorState({
    required WorkoutPlan draft,
    required bool isNew,
    @Default(0) int revision,
    @Default(false) bool isDirty,
    @Default(false) bool isLoading,
    @Default(false) bool isSaving,
    @Default(false) bool saveSuccess,
    @Default(0) int selectedDayIndex,
    @Default(false) bool isAiDraft,

    /// L'ultimo fallimento, da mostrare una volta.
    PlanEditorFailure? failure,
  }) = _PlanEditorState;

  /// La scheda a giorno singolo ha un giorno implicito che l'UI non mostra
  /// (analisi funzionale §5.1): i tab/etichette giorno appaiono solo da 2 in su.
  bool get showDayTabs => draft.days.length > 1;
}
