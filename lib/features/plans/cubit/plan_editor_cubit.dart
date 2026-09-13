import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/entities/block.dart';
import '../../../data/entities/exercise.dart';
import '../../../data/entities/workout_day.dart';
import '../../../data/entities/workout_plan.dart';
import '../../../data/repositories/plan_repository.dart';
import 'plan_editor_labels.dart';
import 'plan_editor_state.dart';

/// Bozza in editing di una scheda (RF-02): CRUD di giorni/blocchi/esercizi,
/// riordino, cambio tipo blocco, dirty check e salvataggio.
///
/// Ogni mutazione lavora in place su [PlanEditorState.draft] e poi emette
/// (vedi nota su `revision` in `plan_editor_state.dart`). Nessuna scrittura
/// sul repository avviene prima di [save].
class PlanEditorCubit extends Cubit<PlanEditorState> {
  PlanEditorCubit.create({
    required PlanRepository repository,
    required PlanEditorLabels labels,
  }) : _repository = repository,
       _labels = labels,
       super(PlanEditorState(draft: _emptyDraft(labels), isNew: true));

  /// Revisione di una bozza non persistita (import AI, RF-03): l'editor parte
  /// già sporco così l'uscita senza salvare chiede conferma e la scheda non
  /// viene mai scritta senza conferma esplicita dell'utente.
  PlanEditorCubit.draft({
    required PlanRepository repository,
    required PlanEditorLabels labels,
    required WorkoutPlan draft,
  }) : _repository = repository,
       _labels = labels,
       super(
         PlanEditorState(
           draft: draft,
           isNew: true,
           isDirty: true,
           isAiDraft: true,
         ),
       ) {
    // L'editor assume almeno un giorno (giorno implicito, §5.1).
    if (draft.days.isEmpty) {
      draft.days.add(WorkoutDay(label: labels.singleDay, sortOrder: 0));
    }
  }

  PlanEditorCubit.edit({
    required PlanRepository repository,
    required PlanEditorLabels labels,
    required int planId,
  }) : _repository = repository,
       _labels = labels,
       super(
         PlanEditorState(
           draft: _emptyDraft(labels),
           isNew: false,
           isLoading: true,
         ),
       ) {
    _load(planId);
  }

  final PlanRepository _repository;
  final PlanEditorLabels _labels;

  static WorkoutPlan _emptyDraft(PlanEditorLabels labels) {
    final now = DateTime.now();
    final plan = WorkoutPlan(name: '', createdAt: now, updatedAt: now);
    plan.days.add(WorkoutDay(label: labels.singleDay, sortOrder: 0));
    return plan;
  }

  void _load(int planId) {
    final plan = _repository.getById(planId);
    if (plan == null) {
      emit(
        state.copyWith(isLoading: false, errorMessage: _labels.planNotFound),
      );
      return;
    }
    emit(state.copyWith(draft: plan, isLoading: false));
  }

  // --- metadati scheda ---

  void updateName(String name) => _mutate((d) => d.name = name);

  void updateDescription(String? description) =>
      _mutate((d) => d.description = _blankToNull(description));

  void updatePlanNotes(String? notes) =>
      _mutate((d) => d.notes = _blankToNull(notes));

  // --- giorni ---

  void addDay() {
    _mutate((d) {
      final order = d.days.length;
      d.days.add(
        WorkoutDay(label: _labels.dayName(_dayLetter(order)), sortOrder: order),
      );
    });
    selectDay(state.draft.days.length - 1);
  }

  void updateDayLabel(int dayIndex, String label) =>
      _mutate((d) => d.days[dayIndex].label = label);

  void updateDayNotes(int dayIndex, String? notes) =>
      _mutate((d) => d.days[dayIndex].notes = _blankToNull(notes));

  /// Resta sempre almeno un giorno: la UI non offre comunque questa azione
  /// finché la scheda è a giorno singolo (§5.1).
  void removeDay(int dayIndex) {
    if (state.draft.days.length <= 1) return;
    final currentSelection = state.selectedDayIndex;
    _mutate((d) {
      d.days.removeAt(dayIndex);
      _reindex(d.days, (day, i) => day.sortOrder = i);
    });
    // Se il giorno rimosso precedeva quello selezionato, la posizione di
    // quest'ultimo si è spostata di uno: senza questo aggiustamento
    // `selectedDayIndex` continuerebbe a puntare al giorno sbagliato.
    final adjustedSelection = dayIndex < currentSelection
        ? currentSelection - 1
        : currentSelection;
    selectDay(adjustedSelection);
  }

  void reorderDays(int oldIndex, int newIndex) {
    _mutate(
      (d) => _reorderAndReindex(
        d.days,
        oldIndex,
        newIndex,
        (day, i) => day.sortOrder = i,
      ),
    );
  }

  void selectDay(int index) {
    final maxIndex = state.draft.days.isEmpty ? 0 : state.draft.days.length - 1;
    emit(state.copyWith(selectedDayIndex: _clampIndex(index, maxIndex)));
  }

  // --- blocchi ---

  void addBlock(int dayIndex, BlockType type) {
    _mutate((d) {
      final day = d.days[dayIndex];
      final block = Block.ofType(type, sortOrder: day.blocks.length);
      _applyDefaultParams(block, type);
      day.blocks.add(block);
    });
  }

  void changeBlockType(int dayIndex, int blockIndex, BlockType type) {
    _mutateBlock(dayIndex, blockIndex, (block) {
      _clearTypeParams(block);
      block.type = type;
      _applyDefaultParams(block, type);
    });
  }

  void updateBlockNotes(int dayIndex, int blockIndex, String? notes) =>
      _mutateBlock(dayIndex, blockIndex, (b) => b.notes = _blankToNull(notes));

  void setBlockIntervalSeconds(int dayIndex, int blockIndex, int? value) =>
      _mutateBlock(dayIndex, blockIndex, (b) => b.intervalSeconds = value);

  void setBlockTotalMinutes(int dayIndex, int blockIndex, int? value) =>
      _mutateBlock(dayIndex, blockIndex, (b) => b.totalMinutes = value);

  void setBlockDurationSeconds(int dayIndex, int blockIndex, int? value) =>
      _mutateBlock(dayIndex, blockIndex, (b) => b.durationSeconds = value);

  void setBlockWorkSeconds(int dayIndex, int blockIndex, int? value) =>
      _mutateBlock(dayIndex, blockIndex, (b) => b.workSeconds = value);

  void setBlockRestSeconds(int dayIndex, int blockIndex, int? value) =>
      _mutateBlock(dayIndex, blockIndex, (b) => b.restSeconds = value);

  void setBlockRounds(int dayIndex, int blockIndex, int? value) =>
      _mutateBlock(dayIndex, blockIndex, (b) => b.rounds = value);

  void setBlockRestBetweenRoundsSeconds(
    int dayIndex,
    int blockIndex,
    int? value,
  ) => _mutateBlock(
    dayIndex,
    blockIndex,
    (b) => b.restBetweenRoundsSeconds = value,
  );

  void setBlockTimeCapSeconds(int dayIndex, int blockIndex, int? value) =>
      _mutateBlock(dayIndex, blockIndex, (b) => b.timeCapSeconds = value);

  void setBlockFreeText(int dayIndex, int blockIndex, String? value) =>
      _mutateBlock(dayIndex, blockIndex, (b) => b.freeTextContent = value);

  void removeBlock(int dayIndex, int blockIndex) {
    _mutate((d) {
      final day = d.days[dayIndex];
      day.blocks.removeAt(blockIndex);
      _reindex(day.blocks, (b, i) => b.sortOrder = i);
    });
  }

  void reorderBlocks(int dayIndex, int oldIndex, int newIndex) {
    _mutate((d) {
      final blocks = d.days[dayIndex].blocks;
      _reorderAndReindex(blocks, oldIndex, newIndex, (b, i) => b.sortOrder = i);
    });
  }

  // --- esercizi ---

  void addExercise(int dayIndex, int blockIndex) {
    _mutateBlock(dayIndex, blockIndex, (block) {
      block.exercises.add(
        Exercise(name: '', sortOrder: block.exercises.length),
      );
    });
  }

  void setExerciseName(
    int dayIndex,
    int blockIndex,
    int exerciseIndex,
    String name,
  ) => _mutateExercise(
    dayIndex,
    blockIndex,
    exerciseIndex,
    (e) => e.name = name,
  );

  void setExerciseSets(
    int dayIndex,
    int blockIndex,
    int exerciseIndex,
    int? sets,
  ) => _mutateExercise(
    dayIndex,
    blockIndex,
    exerciseIndex,
    (e) => e.sets = sets,
  );

  void setExerciseReps(
    int dayIndex,
    int blockIndex,
    int exerciseIndex,
    String? reps,
  ) => _mutateExercise(
    dayIndex,
    blockIndex,
    exerciseIndex,
    (e) => e.reps = _blankToNull(reps),
  );

  void setExerciseLoad(
    int dayIndex,
    int blockIndex,
    int exerciseIndex,
    String? load,
  ) => _mutateExercise(
    dayIndex,
    blockIndex,
    exerciseIndex,
    (e) => e.load = _blankToNull(load),
  );

  void setExerciseRestSeconds(
    int dayIndex,
    int blockIndex,
    int exerciseIndex,
    int? restSeconds,
  ) => _mutateExercise(
    dayIndex,
    blockIndex,
    exerciseIndex,
    (e) => e.restSeconds = restSeconds,
  );

  void setExerciseDurationSeconds(
    int dayIndex,
    int blockIndex,
    int exerciseIndex,
    int? durationSeconds,
  ) => _mutateExercise(
    dayIndex,
    blockIndex,
    exerciseIndex,
    (e) => e.durationSeconds = durationSeconds,
  );

  void setExerciseNotes(
    int dayIndex,
    int blockIndex,
    int exerciseIndex,
    String? notes,
  ) => _mutateExercise(
    dayIndex,
    blockIndex,
    exerciseIndex,
    (e) => e.notes = _blankToNull(notes),
  );

  void removeExercise(int dayIndex, int blockIndex, int exerciseIndex) {
    _mutateBlock(dayIndex, blockIndex, (block) {
      block.exercises.removeAt(exerciseIndex);
      _reindex(block.exercises, (e, i) => e.sortOrder = i);
    });
  }

  void reorderExercises(
    int dayIndex,
    int blockIndex,
    int oldIndex,
    int newIndex,
  ) {
    _mutateBlock(dayIndex, blockIndex, (block) {
      _reorderAndReindex(
        block.exercises,
        oldIndex,
        newIndex,
        (e, i) => e.sortOrder = i,
      );
    });
  }

  // --- salvataggio ---

  void dismissError() => emit(state.copyWith(errorMessage: null));

  Future<bool> save() async {
    final trimmedName = state.draft.name.trim();
    if (trimmedName.isEmpty) {
      emit(state.copyWith(errorMessage: _labels.nameRequired));
      return false;
    }

    emit(state.copyWith(isSaving: true, errorMessage: null));
    try {
      state.draft.name = trimmedName;
      _repository.savePlan(state.draft);
      emit(state.copyWith(isSaving: false, isDirty: false, saveSuccess: true));
      return true;
    } catch (e) {
      emit(state.copyWith(isSaving: false, errorMessage: e.toString()));
      return false;
    }
  }

  // --- helper interni ---

  void _mutate(void Function(WorkoutPlan draft) fn) {
    fn(state.draft);
    emit(state.copyWith(isDirty: true, revision: state.revision + 1));
  }

  void _mutateBlock(
    int dayIndex,
    int blockIndex,
    void Function(Block block) fn,
  ) {
    _mutate((d) => fn(d.days[dayIndex].blocks[blockIndex]));
  }

  void _mutateExercise(
    int dayIndex,
    int blockIndex,
    int exerciseIndex,
    void Function(Exercise exercise) fn,
  ) {
    _mutate(
      (d) => fn(d.days[dayIndex].blocks[blockIndex].exercises[exerciseIndex]),
    );
  }

  void _reindex<T>(List<T> items, void Function(T item, int order) setOrder) {
    for (var i = 0; i < items.length; i++) {
      setOrder(items[i], i);
    }
  }

  void _reorderAndReindex<T>(
    List<T> items,
    int oldIndex,
    int newIndex,
    void Function(T item, int order) setOrder,
  ) {
    var target = newIndex;
    if (target > oldIndex) target -= 1;
    final item = items.removeAt(oldIndex);
    items.insert(target, item);
    _reindex(items, setOrder);
  }

  void _clearTypeParams(Block block) {
    block
      ..intervalSeconds = null
      ..totalMinutes = null
      ..durationSeconds = null
      ..workSeconds = null
      ..restSeconds = null
      ..rounds = null
      ..restBetweenRoundsSeconds = null
      ..timeCapSeconds = null
      ..freeTextContent = null;
  }

  void _applyDefaultParams(Block block, BlockType type) {
    switch (type) {
      case BlockType.standard:
        break;
      case BlockType.superset:
      case BlockType.circuit:
        block
          ..rounds = 3
          ..restBetweenRoundsSeconds = 60;
        break;
      case BlockType.emom:
        block
          ..intervalSeconds = 60
          ..totalMinutes = 10;
        break;
      case BlockType.amrap:
        block.durationSeconds = 900;
        break;
      case BlockType.tabata:
        block
          ..workSeconds = 20
          ..restSeconds = 10
          ..rounds = 8;
        break;
      case BlockType.forTime:
        break; // timeCapSeconds è opzionale (§5.2)
      case BlockType.freeText:
        block.freeTextContent = '';
        break;
    }
  }

  static String _dayLetter(int zeroBasedIndex) {
    // A, B, C, ... Z, poi AA, AB, ... (improbabile servano più di 26 giorni).
    var n = zeroBasedIndex;
    final buffer = StringBuffer();
    do {
      buffer.write(String.fromCharCode(65 + n % 26));
      n = n ~/ 26 - 1;
    } while (n >= 0);
    return buffer.toString().split('').reversed.join();
  }

  static int _clampIndex(int value, int maxIndex) {
    if (value < 0) return 0;
    if (value > maxIndex) return maxIndex;
    return value;
  }

  String? _blankToNull(String? value) {
    if (value == null) return null;
    return value.trim().isEmpty ? null : value;
  }
}
