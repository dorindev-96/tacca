import 'dart:async';

import 'package:tacca/data/entities/workout_plan.dart';
import 'package:tacca/data/repositories/plan_repository.dart';
import 'package:tacca/features/plans/cubit/plans_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockPlanRepository extends Mock implements PlanRepository {}

WorkoutPlan _plan(int id, String name, {bool isActive = false}) {
  final now = DateTime(2026, 1, 1);
  return WorkoutPlan(
    name: name,
    createdAt: now,
    updatedAt: now,
    isActive: isActive,
  )..id = id;
}

void main() {
  late _MockPlanRepository repository;
  late StreamController<List<WorkoutPlan>> activeController;
  late StreamController<List<WorkoutPlan>> archivedController;

  setUp(() {
    repository = _MockPlanRepository();
    activeController = StreamController<List<WorkoutPlan>>.broadcast();
    archivedController = StreamController<List<WorkoutPlan>>.broadcast();
    when(
      () => repository.watchActive(),
    ).thenAnswer((_) => activeController.stream);
    when(
      () => repository.watchArchived(),
    ).thenAnswer((_) => archivedController.stream);
  });

  tearDown(() async {
    await activeController.close();
    await archivedController.close();
  });

  group('PlansCubit', () {
    test(
      'parte in caricamento e si aggiorna quando entrambi gli stream emettono',
      () async {
        final cubit = PlansCubit(repository: repository);
        expect(cubit.state.isLoading, isTrue);

        final active = _plan(1, 'Push / Pull / Legs');
        final archived = _plan(2, 'Vecchia scheda');
        activeController.add([active]);
        await pumpEventQueue();
        expect(
          cubit.state.isLoading,
          isTrue,
          reason: 'manca ancora lo stream archiviate',
        );

        archivedController.add([archived]);
        await pumpEventQueue();

        expect(cubit.state.isLoading, isFalse);
        expect(cubit.state.activePlans, [active]);
        expect(cubit.state.archivedPlans, [archived]);

        await cubit.close();
      },
    );

    test(
      'inUsePlan espone la scheda con isActive=true tra le attive',
      () async {
        final cubit = PlansCubit(repository: repository);
        final inUse = _plan(1, 'In uso', isActive: true);
        final other = _plan(2, 'Altra');
        activeController.add([inUse, other]);
        archivedController.add([]);
        await pumpEventQueue();

        expect(cubit.state.inUsePlan, inUse);

        await cubit.close();
      },
    );

    test(
      'search filtra le liste per nome, senza distinzione maiuscole/minuscole',
      () async {
        final cubit = PlansCubit(repository: repository);
        activeController.add([
          _plan(1, 'Push Pull Legs'),
          _plan(2, 'Full Body'),
        ]);
        archivedController.add([_plan(3, 'Vecchio Push')]);
        await pumpEventQueue();

        cubit.search('push');

        expect(cubit.state.filteredActivePlans.map((p) => p.name), [
          'Push Pull Legs',
        ]);
        expect(cubit.state.filteredArchivedPlans.map((p) => p.name), [
          'Vecchio Push',
        ]);
        // Le liste non filtrate restano intatte.
        expect(cubit.state.activePlans, hasLength(2));

        await cubit.close();
      },
    );

    test('setActivePlan delega al repository', () async {
      when(() => repository.setActivePlan(any())).thenReturn(null);
      final cubit = PlansCubit(repository: repository);

      cubit.setActivePlan(7);

      verify(() => repository.setActivePlan(7)).called(1);
      await cubit.close();
    });

    test(
      'duplicatePlan, setArchived e deletePlan delegano al repository',
      () async {
        when(() => repository.duplicatePlan(any())).thenReturn(99);
        when(
          () => repository.setArchived(any(), archived: any(named: 'archived')),
        ).thenReturn(null);
        when(() => repository.deletePlan(any())).thenReturn(null);
        final cubit = PlansCubit(repository: repository);

        cubit.duplicatePlan(1);
        cubit.setArchived(2, archived: true);
        cubit.setArchived(3, archived: false);
        cubit.deletePlan(4);

        verify(() => repository.duplicatePlan(1)).called(1);
        verify(() => repository.setArchived(2, archived: true)).called(1);
        verify(() => repository.setArchived(3, archived: false)).called(1);
        verify(() => repository.deletePlan(4)).called(1);

        await cubit.close();
      },
    );

    test(
      'un\'eccezione del repository imposta errorMessage, dismissError lo pulisce',
      () async {
        when(() => repository.deletePlan(any())).thenThrow(StateError('boom'));
        final cubit = PlansCubit(repository: repository);

        cubit.deletePlan(1);
        await pumpEventQueue();

        expect(cubit.state.errorMessage, contains('boom'));

        cubit.dismissError();
        expect(cubit.state.errorMessage, isNull);

        await cubit.close();
      },
    );
  });
}
