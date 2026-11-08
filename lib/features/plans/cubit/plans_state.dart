import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../data/entities/workout_plan.dart';

part 'plans_state.freezed.dart';

/// Quale azione sull'archivio non è riuscita: alla pagina serve solo per
/// scegliere il messaggio.
enum PlansFailure { setActive, duplicate, archive, restore, delete }

/// Stato dell'archivio schede (RF-01): liste attiva/archiviata già filtrate
/// per [searchQuery], così la UI legge direttamente i getter senza rifiltrare.
@freezed
sealed class PlansState with _$PlansState {
  const PlansState._();

  const factory PlansState({
    @Default(true) bool isLoading,
    @Default([]) List<WorkoutPlan> activePlans,
    @Default([]) List<WorkoutPlan> archivedPlans,
    @Default('') String searchQuery,

    /// L'ultima azione fallita, da mostrare una volta.
    PlansFailure? failure,
  }) = _PlansState;

  /// La scheda marcata "in uso", se c'è e risponde alla ricerca (mai tra le
  /// archiviate).
  WorkoutPlan? get inUsePlan =>
      filteredActivePlans.where((plan) => plan.isActive).firstOrNull;

  /// La scheda [id], attiva o archiviata; null se non esiste (più).
  WorkoutPlan? planById(int id) => [
    ...activePlans,
    ...archivedPlans,
  ].where((plan) => plan.id == id).firstOrNull;

  List<WorkoutPlan> get filteredActivePlans => _filtered(activePlans);

  List<WorkoutPlan> get filteredArchivedPlans => _filtered(archivedPlans);

  List<WorkoutPlan> _filtered(List<WorkoutPlan> plans) {
    final query = searchQuery.trim().toLowerCase();
    if (query.isEmpty) return plans;
    return plans.where((p) => p.name.toLowerCase().contains(query)).toList();
  }
}
