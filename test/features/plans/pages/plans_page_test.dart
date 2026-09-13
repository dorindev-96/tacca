import 'dart:async';

import 'package:tacca/data/entities/workout_plan.dart';
import 'package:tacca/data/repositories/plan_repository.dart';
import 'package:tacca/data/entities/workout_log.dart';
import 'package:tacca/features/plans/cubit/plans_cubit.dart';
import 'package:tacca/features/plans/pages/plans_page.dart';
import 'package:tacca/features/workout/cubit/active_session_cubit.dart';
import 'package:tacca/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/fakes.dart';

class _MockPlanRepository extends Mock implements PlanRepository {}

WorkoutPlan _plan(
  int id,
  String name, {
  bool isArchived = false,
  bool isActive = false,
}) {
  final now = DateTime(2026, 1, 1);
  return WorkoutPlan(
    name: name,
    createdAt: now,
    updatedAt: now,
    isArchived: isArchived,
    isActive: isActive,
  )..id = id;
}

void main() {
  // La card della sessione in corso mostra l'ora di inizio, che passa da
  // DateFormat: senza simboli caricati non si formatta.
  setUpAll(() => initializeDateFormatting('it'));

  late _MockPlanRepository repository;
  late FakeWorkoutLogRepository logs;
  late StreamController<List<WorkoutPlan>> activeController;
  late StreamController<List<WorkoutPlan>> archivedController;

  setUp(() {
    repository = _MockPlanRepository();
    logs = FakeWorkoutLogRepository();
    activeController = StreamController<List<WorkoutPlan>>.broadcast();
    archivedController = StreamController<List<WorkoutPlan>>.broadcast();
    when(
      () => repository.watchActive(),
    ).thenAnswer((_) => activeController.stream);
    when(
      () => repository.watchArchived(),
    ).thenAnswer((_) => archivedController.stream);
    when(() => repository.duplicatePlan(any())).thenReturn(99);
    when(
      () => repository.setArchived(any(), archived: any(named: 'archived')),
    ).thenReturn(null);
  });

  tearDown(() async {
    await activeController.close();
    await archivedController.close();
    await logs.dispose();
  });

  Future<void> pumpPlansPage(
    WidgetTester tester, {
    List<WorkoutPlan> active = const [],
    List<WorkoutPlan> archived = const [],
  }) async {
    await tester.pumpWidget(
      BlocProvider<ActiveSessionCubit>(
        create: (context) => ActiveSessionCubit(repository: logs),
        child: MaterialApp.router(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          // I test verificano le stringhe italiane: senza fissare la lingua
          // la locale di test (en_US) non è fra quelle tradotte e Flutter
          // ripiegherebbe sulla prima in ordine alfabetico, il tedesco.
          locale: const Locale('it'),
          routerConfig: GoRouter(
            initialLocation: '/',
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => BlocProvider(
                  create: (context) => PlansCubit(repository: repository),
                  child: const PlansPage(),
                ),
              ),
              GoRoute(
                path: '/plans/new',
                builder: (context, state) =>
                    const Scaffold(body: Text('NUOVA SCHEDA')),
              ),
              GoRoute(
                path: '/plans/new/import',
                builder: (context, state) =>
                    const Scaffold(body: Text('IMPORT AI')),
              ),
              GoRoute(
                path: '/plans/new/import/paste',
                builder: (context, state) =>
                    const Scaffold(body: Text('IMPORT CHAT')),
              ),
              GoRoute(
                path: '/workout/:logId',
                builder: (context, state) => Scaffold(
                  body: Text('SESSIONE ${state.pathParameters['logId']}'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    activeController.add(active);
    archivedController.add(archived);
    await tester.pumpAndSettle();
  }

  testWidgets('stato vuoto quando non ci sono schede', (tester) async {
    await pumpPlansPage(tester);

    expect(
      find.text('Nessuna scheda. Creane una per iniziare.'),
      findsOneWidget,
    );
  });

  testWidgets('la ricerca filtra la lista per nome', (tester) async {
    await pumpPlansPage(
      tester,
      active: [_plan(1, 'Push Pull Legs'), _plan(2, 'Full Body')],
    );

    expect(find.text('Push Pull Legs'), findsOneWidget);
    expect(find.text('Full Body'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'push');
    await tester.pumpAndSettle();

    expect(find.text('Push Pull Legs'), findsOneWidget);
    expect(find.text('Full Body'), findsNothing);
  });

  testWidgets('la scheda in uso compare in evidenza in una sezione dedicata', (
    tester,
  ) async {
    await pumpPlansPage(
      tester,
      active: [_plan(1, 'In uso', isActive: true), _plan(2, 'Altra scheda')],
    );

    expect(find.text('In uso'), findsWidgets); // badge sezione + nome scheda
    expect(find.text('Altra scheda'), findsOneWidget);
  });

  testWidgets('il FAB offre editor manuale e le due strade AI (RF-02/RF-03)', (
    tester,
  ) async {
    await pumpPlansPage(tester, active: [_plan(1, 'Push Pull Legs')]);

    await tester.tap(find.text('Nuova scheda'));
    await tester.pumpAndSettle();

    expect(find.text('Editor manuale'), findsOneWidget);
    expect(find.text('Con AI'), findsOneWidget);
    expect(find.text('Con la tua chat AI'), findsOneWidget);

    await tester.tap(find.text('Editor manuale'));
    await tester.pumpAndSettle();

    expect(find.text('NUOVA SCHEDA'), findsOneWidget);
  });

  testWidgets('dal FAB si raggiunge la chat AI esterna', (tester) async {
    await pumpPlansPage(tester, active: [_plan(1, 'Push Pull Legs')]);

    await tester.tap(find.text('Nuova scheda'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Con la tua chat AI'));
    await tester.pumpAndSettle();

    expect(find.text('IMPORT CHAT'), findsOneWidget);
  });

  testWidgets('dal FAB si raggiunge l\'import AI', (tester) async {
    await pumpPlansPage(tester, active: [_plan(1, 'Push Pull Legs')]);

    await tester.tap(find.text('Nuova scheda'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Con AI'));
    await tester.pumpAndSettle();

    expect(find.text('IMPORT AI'), findsOneWidget);
  });

  testWidgets('duplica una scheda dal menu azioni', (tester) async {
    await pumpPlansPage(tester, active: [_plan(1, 'Push Pull Legs')]);

    await tester.tap(find.byWidgetPredicate((w) => w is PopupMenuButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duplica'));
    await tester.pumpAndSettle();

    verify(() => repository.duplicatePlan(1)).called(1);
  });

  testWidgets('la sessione in corso apre l\'allenamento dalla card in cima', (
    tester,
  ) async {
    logs.saveLog(
      WorkoutLog.start(
        startedAt: DateTime(2026, 8, 15, 18, 30),
        planNameSnapshot: 'Push Pull Legs',
        dayLabelSnapshot: 'Giorno A',
      ),
    );

    await pumpPlansPage(tester, active: [_plan(1, 'Push Pull Legs')]);

    expect(find.text('Allenamento in corso'), findsOneWidget);
    expect(find.text('Iniziato alle 18:30'), findsOneWidget);

    await tester.tap(find.text('Allenamento in corso'));
    await tester.pumpAndSettle();

    expect(find.text('SESSIONE 1'), findsOneWidget);
  });

  testWidgets('senza sessioni aperte la card non compare', (tester) async {
    await pumpPlansPage(tester, active: [_plan(1, 'Push Pull Legs')]);

    expect(find.text('Allenamento in corso'), findsNothing);
  });

  testWidgets('archivia una scheda dal menu azioni', (tester) async {
    await pumpPlansPage(tester, active: [_plan(1, 'Push Pull Legs')]);

    await tester.tap(find.byWidgetPredicate((w) => w is PopupMenuButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archivia'));
    await tester.pumpAndSettle();

    verify(() => repository.setArchived(1, archived: true)).called(1);
  });
}
