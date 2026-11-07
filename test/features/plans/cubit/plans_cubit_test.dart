import 'dart:async';

import 'package:tacca/data/entities/workout_plan.dart';
import 'package:tacca/data/repositories/plan_repository.dart';
import 'package:tacca/features/plans/cubit/plans_cubit.dart';
import 'package:tacca/features/plans/cubit/plans_state.dart';
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
  late StreamController<PlanArchive> plansController;

  setUp(() {
    repository = _MockPlanRepository();
    plansController = StreamController<PlanArchive>.broadcast();
    when(
      () => repository.watchPlans(),
    ).thenAnswer((_) => plansController.stream);
  });

  tearDown(() async {
    await plansController.close();
  });

  group('PlansCubit', () {
    test(
      'parte in caricamento e si aggiorna con un\'emissione sola per entrambe le liste',
      () async {
        final cubit = PlansCubit(repository: repository);
        expect(cubit.state.isLoading, isTrue);

        final states = <Object>[];
        final sub = cubit.stream.listen(states.add);

        final active = _plan(1, 'Push / Pull / Legs');
        final archived = _plan(2, 'Vecchia scheda');
        plansController.add(
          PlanArchive(active: [active], archived: [archived]),
        );
        await pumpEventQueue();

        expect(cubit.state.isLoading, isFalse);
        expect(cubit.state.activePlans, [active]);
        expect(cubit.state.archivedPlans, [archived]);
        expect(states, hasLength(1), reason: 'una scrittura, un\'emissione');

        await sub.cancel();
        await cubit.close();
      },
    );

    test(
      'inUsePlan espone la scheda con isActive=true tra le attive',
      () async {
        final cubit = PlansCubit(repository: repository);
        final inUse = _plan(1, 'In uso', isActive: true);
        final other = _plan(2, 'Altra');
        plansController.add(PlanArchive(active: [inUse, other]));
        await pumpEventQueue();

        expect(cubit.state.inUsePlan, inUse);

        await cubit.close();
      },
    );

    test(
      'search filtra le liste per nome, senza distinzione maiuscole/minuscole',
      () async {
        final cubit = PlansCubit(repository: repository);
        plansController.add(
          PlanArchive(
            active: [_plan(1, 'Push Pull Legs'), _plan(2, 'Full Body')],
            archived: [_plan(3, 'Vecchio Push')],
          ),
        );
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
      'un\'eccezione del repository dice quale azione è fallita, non il suo testo',
      () async {
        when(() => repository.deletePlan(any())).thenThrow(StateError('boom'));
        final cubit = PlansCubit(repository: repository);

        cubit.deletePlan(1);
        await pumpEventQueue();

        expect(cubit.state.failure, PlansFailure.delete);

        cubit.dismissError();
        expect(cubit.state.failure, isNull);

        // Archiviare e ripristinare sono due messaggi diversi.
        when(
          () => repository.setArchived(any(), archived: any(named: 'archived')),
        ).thenThrow(StateError('boom'));
        cubit.setArchived(1, archived: false);
        expect(cubit.state.failure, PlansFailure.restore);

        await cubit.close();
      },
    );
  });
}
