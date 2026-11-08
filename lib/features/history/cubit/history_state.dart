import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../data/entities/workout_log.dart';

part 'history_state.freezed.dart';

/// Stato dello storico allenamenti (RF-07).
///
/// Il filtro lavora sul **nome snapshot** della scheda, non sul riferimento:
/// lo storico è snapshot-based (§4), quindi le sessioni di una scheda
/// eliminata restano raggruppate e filtrabili come tutte le altre.
@freezed
sealed class HistoryState with _$HistoryState {
  const HistoryState._();

  const factory HistoryState({
    @Default(true) bool isLoading,
    @Default([]) List<WorkoutLog> logs,

    /// `null` = nessun filtro (tutte le schede).
    String? planFilter,

    /// L'eliminazione di una voce non è riuscita: da mostrare una volta.
    @Default(false) bool deleteFailed,
  }) = _HistoryState;

  List<WorkoutLog> get filteredLogs {
    final filter = planFilter;
    if (filter == null) return logs;
    return logs.where((log) => log.planNameSnapshot == filter).toList();
  }

  /// Schede che compaiono nello storico, in ordine di prima apparizione
  /// (i log sono già ordinati dal più recente).
  List<String> get planOptions {
    final seen = <String>{};
    return [
      for (final log in logs)
        if (seen.add(log.planNameSnapshot)) log.planNameSnapshot,
    ];
  }
}
