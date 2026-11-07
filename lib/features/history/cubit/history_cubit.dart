import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/entities/workout_log.dart';
import '../../../data/repositories/workout_log_repository.dart';
import 'history_state.dart';

/// Storico delle sessioni (RF-07): elenco per data, filtro per scheda,
/// eliminazione di una singola voce.
///
/// Come [PlansCubit], le mutazioni non toccano lo stato: chiamano il
/// repository e lasciano che lo stream ripropaghi l'elenco aggiornato.
class HistoryCubit extends Cubit<HistoryState> {
  HistoryCubit({required WorkoutLogRepository repository})
    : _repository = repository,
      super(const HistoryState()) {
    _subscription = _repository.watchFinished().listen(_onLogsChanged);
  }

  final WorkoutLogRepository _repository;
  late final StreamSubscription<List<WorkoutLog>> _subscription;

  void _onLogsChanged(List<WorkoutLog> logs) {
    emit(state.copyWith(logs: logs, isLoading: false));
  }

  /// `null` rimuove il filtro.
  void filterByPlan(String? planName) =>
      emit(state.copyWith(planFilter: planName));

  void deleteLog(int logId) {
    try {
      _repository.deleteLog(logId);
    } catch (_) {
      emit(state.copyWith(deleteFailed: true));
    }
  }

  void dismissError() => emit(state.copyWith(deleteFailed: false));

  @override
  Future<void> close() async {
    await _subscription.cancel();
    return super.close();
  }
}
