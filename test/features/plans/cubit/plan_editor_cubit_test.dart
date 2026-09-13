import 'package:tacca/data/entities/block.dart';
import 'package:tacca/data/entities/workout_day.dart';
import 'package:tacca/data/entities/workout_plan.dart';
import 'package:tacca/data/repositories/plan_repository.dart';
import 'package:tacca/features/plans/cubit/plan_editor_cubit.dart';
import 'package:tacca/features/plans/cubit/plan_editor_labels.dart';
import 'package:tacca/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockPlanRepository extends Mock implements PlanRepository {}

void main() {
  late _MockPlanRepository repository;

  // Le etichette vere, non un segnaposto: i test qui sotto verificano proprio
  // i nomi che finiscono dentro la scheda ("Giorno unico", "Giorno C").
  final editorLabels = PlanEditorLabels.of(
    lookupAppLocalizations(const Locale('it')),
  );

  setUpAll(() {
    registerFallbackValue(
      WorkoutPlan(
        name: '',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    );
  });

  setUp(() {
    repository = _MockPlanRepository();
  });

  group('PlanEditorCubit.create', () {
    test('parte con un giorno implicito nascosto e nessuna modifica', () {
      final cubit = PlanEditorCubit.create(
        repository: repository,
        labels: editorLabels,
      );

      expect(cubit.state.isNew, isTrue);
      expect(cubit.state.isDirty, isFalse);
      expect(cubit.state.draft.days, hasLength(1));
      expect(cubit.state.showDayTabs, isFalse);
    });

    test('updateName imposta il nome e marca la bozza come modificata', () {
      final cubit = PlanEditorCubit.create(
        repository: repository,
        labels: editorLabels,
      );

      cubit.updateName('Upper / Lower');

      expect(cubit.state.draft.name, 'Upper / Lower');
      expect(cubit.state.isDirty, isTrue);
    });

    test('addDay aggiunge un giorno, lo seleziona e mostra i tab', () {
      final cubit = PlanEditorCubit.create(
        repository: repository,
        labels: editorLabels,
      );

      cubit.addDay();

      expect(cubit.state.draft.days, hasLength(2));
      expect(cubit.state.showDayTabs, isTrue);
      expect(cubit.state.selectedDayIndex, 1);
    });

    test('removeDay non ha effetto quando resta un solo giorno', () {
      final cubit = PlanEditorCubit.create(
        repository: repository,
        labels: editorLabels,
      );

      cubit.removeDay(0);

      expect(cubit.state.draft.days, hasLength(1));
      expect(cubit.state.isDirty, isFalse);
    });

    test('removeDay rimuove e riassegna sortOrder in ordine', () {
      final cubit = PlanEditorCubit.create(
        repository: repository,
        labels: editorLabels,
      );
      cubit.addDay(); // 2 giorni: A(0), B(1)
      cubit.addDay(); // 3 giorni: A(0), B(1), C(2)

      cubit.removeDay(1); // rimuove B

      final labels = cubit.state.draft.days.map((d) => d.label).toList();
      final orders = cubit.state.draft.days.map((d) => d.sortOrder).toList();
      expect(labels, ['Giorno unico', 'Giorno C']);
      expect(orders, [0, 1]);
    });

    test(
      'removeDay di un giorno precedente al selezionato aggiorna selectedDayIndex sullo stesso giorno logico',
      () {
        final cubit = PlanEditorCubit.create(
          repository: repository,
          labels: editorLabels,
        );
        cubit.addDay(); // Giorno unico(0), Giorno B(1)
        cubit.addDay(); // Giorno unico(0), Giorno B(1), Giorno C(2)
        cubit.selectDay(2); // seleziona "Giorno C"
        expect(
          cubit.state.draft.days[cubit.state.selectedDayIndex].label,
          'Giorno C',
        );

        cubit.removeDay(
          0,
        ); // rimuove "Giorno unico", precede quello selezionato

        // "Giorno C" ora è all'indice 1: la selezione deve seguirlo, non restare a 2.
        expect(cubit.state.selectedDayIndex, 1);
        expect(
          cubit.state.draft.days[cubit.state.selectedDayIndex].label,
          'Giorno C',
        );
      },
    );

    test('reorderDays riordina e riassegna sortOrder', () {
      final cubit = PlanEditorCubit.create(
        repository: repository,
        labels: editorLabels,
      );
      cubit.addDay();
      cubit.addDay();
      final before = cubit.state.draft.days.map((d) => d.label).toList();
      expect(before, ['Giorno unico', 'Giorno B', 'Giorno C']);

      cubit.reorderDays(0, 2); // sposta "Giorno unico" dopo "Giorno B"

      final after = cubit.state.draft.days.toList();
      expect(after.map((d) => d.label), [
        'Giorno B',
        'Giorno unico',
        'Giorno C',
      ]);
      expect(after.map((d) => d.sortOrder), [0, 1, 2]);
    });

    test('addBlock applica i parametri di default del tipo scelto', () {
      final cubit = PlanEditorCubit.create(
        repository: repository,
        labels: editorLabels,
      );

      cubit.addBlock(0, BlockType.emom);

      final block = cubit.state.draft.days[0].blocks.single;
      expect(block.type, BlockType.emom);
      expect(block.intervalSeconds, 60);
      expect(block.totalMinutes, 10);
      expect(block.workSeconds, isNull);
    });

    test(
      'changeBlockType pulisce i parametri del tipo precedente prima di applicare i nuovi',
      () {
        final cubit = PlanEditorCubit.create(
          repository: repository,
          labels: editorLabels,
        );
        cubit.addBlock(0, BlockType.emom);

        cubit.changeBlockType(0, 0, BlockType.tabata);

        final block = cubit.state.draft.days[0].blocks.single;
        expect(block.type, BlockType.tabata);
        expect(
          block.intervalSeconds,
          isNull,
          reason: 'parametro emom non più pertinente',
        );
        expect(block.totalMinutes, isNull);
        expect(block.workSeconds, 20);
        expect(block.restSeconds, 10);
        expect(block.rounds, 8);
      },
    );

    test(
      'changeBlockType verso freeText imposta contenuto vuoto editabile',
      () {
        final cubit = PlanEditorCubit.create(
          repository: repository,
          labels: editorLabels,
        );
        cubit.addBlock(0, BlockType.standard);

        cubit.changeBlockType(0, 0, BlockType.freeText);

        expect(cubit.state.draft.days[0].blocks.single.freeTextContent, '');
      },
    );

    test('esercizi: add / update / remove / reorder aggiornano il blocco', () {
      final cubit = PlanEditorCubit.create(
        repository: repository,
        labels: editorLabels,
      );
      cubit.addBlock(0, BlockType.standard);

      cubit.addExercise(0, 0);
      cubit.addExercise(0, 0);
      cubit.setExerciseName(0, 0, 0, 'Panca piana');
      cubit.setExerciseSets(0, 0, 0, 4);
      cubit.setExerciseReps(0, 0, 0, '8-12');
      cubit.setExerciseName(0, 0, 1, 'Rematore');

      var exercises = cubit.state.draft.days[0].blocks[0].exercises;
      expect(exercises.map((e) => e.name), ['Panca piana', 'Rematore']);
      expect(exercises.first.sets, 4);
      expect(exercises.first.reps, '8-12');

      cubit.reorderExercises(0, 0, 0, 2); // Panca piana dopo Rematore
      exercises = cubit.state.draft.days[0].blocks[0].exercises;
      expect(exercises.map((e) => e.name), ['Rematore', 'Panca piana']);
      expect(exercises.map((e) => e.sortOrder), [0, 1]);

      cubit.removeExercise(0, 0, 0);
      exercises = cubit.state.draft.days[0].blocks[0].exercises;
      expect(exercises.map((e) => e.name), ['Panca piana']);
      expect(exercises.single.sortOrder, 0);
    });

    test(
      'save con nome vuoto imposta un errore e non chiama il repository',
      () async {
        final cubit = PlanEditorCubit.create(
          repository: repository,
          labels: editorLabels,
        );

        final ok = await cubit.save();

        expect(ok, isFalse);
        expect(cubit.state.errorMessage, isNotNull);
        verifyNever(() => repository.savePlan(any()));
      },
    );

    test(
      'save con nome valido chiama il repository e pulisce isDirty',
      () async {
        when(() => repository.savePlan(any())).thenReturn(42);
        final cubit = PlanEditorCubit.create(
          repository: repository,
          labels: editorLabels,
        );
        cubit.updateName('  Push Pull Legs  ');

        final ok = await cubit.save();

        expect(ok, isTrue);
        expect(cubit.state.draft.name, 'Push Pull Legs');
        expect(cubit.state.isDirty, isFalse);
        expect(cubit.state.saveSuccess, isTrue);
        verify(() => repository.savePlan(any())).called(1);
      },
    );

    test(
      'save propaga un errore del repository senza interrompere l\'editor',
      () async {
        when(
          () => repository.savePlan(any()),
        ).thenThrow(StateError('disco pieno'));
        final cubit = PlanEditorCubit.create(
          repository: repository,
          labels: editorLabels,
        );
        cubit.updateName('Scheda');

        final ok = await cubit.save();

        expect(ok, isFalse);
        expect(cubit.state.isSaving, isFalse);
        expect(cubit.state.errorMessage, contains('disco pieno'));
      },
    );
  });

  group('PlanEditorCubit.edit', () {
    test('carica la scheda esistente dal repository', () {
      final plan = WorkoutPlan(
        name: 'Scheda esistente',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      )..id = 5;
      plan.days.add(WorkoutDay(label: 'Giorno A', sortOrder: 0));
      when(() => repository.getById(5)).thenReturn(plan);

      final cubit = PlanEditorCubit.edit(
        repository: repository,
        labels: editorLabels,
        planId: 5,
      );

      expect(cubit.state.isLoading, isFalse);
      expect(cubit.state.isNew, isFalse);
      expect(cubit.state.draft.name, 'Scheda esistente');
      expect(cubit.state.isDirty, isFalse);
    });

    test('scheda non trovata imposta un messaggio di errore', () {
      when(() => repository.getById(99)).thenReturn(null);

      final cubit = PlanEditorCubit.edit(
        repository: repository,
        labels: editorLabels,
        planId: 99,
      );

      expect(cubit.state.isLoading, isFalse);
      expect(cubit.state.errorMessage, isNotNull);
    });
  });
}
