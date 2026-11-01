import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/entities/workout_plan.dart';
import '../../../data/repositories/plan_repository.dart';
import 'plans_state.dart';

/// Gestisce l'archivio schede (RF-01): sottoscrive le liste reattive del
/// repository e espone le azioni di lista (attiva/duplica/archivia/elimina).
///
/// Le mutazioni non aggiornano lo stato direttamente: chiamano il repository
/// e lasciano che i due stream (`watchActive`/`watchArchived`) ripropaghino
/// il nuovo elenco, così un'unica fonte di verità decide l'ordinamento.
class PlansCubit extends Cubit<PlansState> {
  PlansCubit({required PlanRepository repository})
    : _repository = repository,
      super(const PlansState()) {
    _activeSub = _repository.watchActive().listen(_onActiveChanged);
    _archivedSub = _repository.watchArchived().listen(_onArchivedChanged);
  }

  final PlanRepository _repository;
  late final StreamSubscription<List<WorkoutPlan>> _activeSub;
  late final StreamSubscription<List<WorkoutPlan>> _archivedSub;

  bool _activeLoaded = false;
  bool _archivedLoaded = false;

  void _onActiveChanged(List<WorkoutPlan> plans) {
    _activeLoaded = true;
    emit(state.copyWith(activePlans: plans, isLoading: !_bothLoaded));
  }

  void _onArchivedChanged(List<WorkoutPlan> plans) {
    _archivedLoaded = true;
    emit(state.copyWith(archivedPlans: plans, isLoading: !_bothLoaded));
  }

  bool get _bothLoaded => _activeLoaded && _archivedLoaded;

  void search(String query) => emit(state.copyWith(searchQuery: query));

  void setActivePlan(int planId) =>
      _guard(() => _repository.setActivePlan(planId));

  void duplicatePlan(int planId) =>
      _guard(() => _repository.duplicatePlan(planId));

  /// Archivia ([archived] `true`) o ripristina la scheda.
  void setArchived(int planId, {required bool archived}) =>
      _guard(() => _repository.setArchived(planId, archived: archived));

  void deletePlan(int planId) => _guard(() => _repository.deletePlan(planId));

  void dismissError() => emit(state.copyWith(errorMessage: null));

  void _guard(void Function() action) {
    try {
      action();
    } catch (e) {
      emit(state.copyWith(errorMessage: e.toString()));
    }
  }

  @override
  Future<void> close() async {
    await _activeSub.cancel();
    await _archivedSub.cancel();
    return super.close();
  }
}
