import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/repositories/plan_repository.dart';
import 'plans_state.dart';

/// Gestisce l'archivio schede (RF-01): sottoscrive le liste reattive del
/// repository e espone le azioni di lista (attiva/duplica/archivia/elimina).
///
/// Le mutazioni non aggiornano lo stato direttamente: chiamano il repository
/// e lasciano che lo stream (`watchPlans`) ripropaghi il nuovo archivio, così
/// un'unica fonte di verità decide l'ordinamento. Una scrittura, un'emissione:
/// i due elenchi arrivano insieme.
class PlansCubit extends Cubit<PlansState> {
  PlansCubit({required PlanRepository repository})
    : _repository = repository,
      super(const PlansState()) {
    _subscription = _repository.watchPlans().listen(_onPlansChanged);
  }

  final PlanRepository _repository;
  late final StreamSubscription<PlanArchive> _subscription;

  void _onPlansChanged(PlanArchive archive) {
    emit(
      state.copyWith(
        activePlans: archive.active,
        archivedPlans: archive.archived,
        isLoading: false,
      ),
    );
  }

  void search(String query) => emit(state.copyWith(searchQuery: query));

  void setActivePlan(int planId) =>
      _guard(PlansFailure.setActive, () => _repository.setActivePlan(planId));

  void duplicatePlan(int planId) =>
      _guard(PlansFailure.duplicate, () => _repository.duplicatePlan(planId));

  /// Archivia ([archived] `true`) o ripristina la scheda.
  void setArchived(int planId, {required bool archived}) => _guard(
    archived ? PlansFailure.archive : PlansFailure.restore,
    () => _repository.setArchived(planId, archived: archived),
  );

  void deletePlan(int planId) =>
      _guard(PlansFailure.delete, () => _repository.deletePlan(planId));

  void dismissError() => emit(state.copyWith(failure: null));

  /// Esegue [action]; se fallisce, lo stato dice **quale** azione, non il
  /// testo dell'eccezione (un messaggio di ObjectBox non è per l'utente).
  void _guard(PlansFailure failure, void Function() action) {
    try {
      action();
    } catch (_) {
      emit(state.copyWith(failure: failure));
    }
  }

  @override
  Future<void> close() async {
    await _subscription.cancel();
    return super.close();
  }
}
