import 'package:tacca/core/widgets/app_sheet.dart';
import 'package:tacca/data/entities/block.dart';
import 'package:tacca/data/entities/exercise.dart';
import 'package:tacca/data/entities/workout_day.dart';
import 'package:tacca/data/entities/workout_log.dart';
import 'package:tacca/data/entities/workout_plan.dart';
import 'package:tacca/features/plans/cubit/plans_cubit.dart';
import 'package:tacca/features/plans/pages/plan_detail_page.dart';
import 'package:tacca/features/plans/widgets/plan_share_image.dart';
import 'package:tacca/features/workout/cubit/active_session_cubit.dart';
import 'package:tacca/l10n/app_localizations.dart';
import 'package:tacca/services/share/image_share_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart' hide Block;

import '../../../support/fakes.dart';

/// Avvio di una sessione dal dettaglio scheda (RF-06), con la regola che ne
/// ammette **una sola per volta**, e condivisione della scheda come immagine.
///
/// Le due rotte della sessione sono sostituite da due schermate finte: qui
/// interessa quale delle due si apre, non cosa fa il Bloc una volta dentro.
void main() {
  late FakePlanRepository plans;
  late FakeWorkoutLogRepository logs;
  late RecordingImageShareService sharer;

  setUp(() {
    plans = FakePlanRepository();
    logs = FakeWorkoutLogRepository();
    sharer = RecordingImageShareService();
  });

  tearDown(() => logs.dispose());

  WorkoutPlan seedPlan({int days = 1}) {
    final now = DateTime(2026, 1, 1);
    final plan = WorkoutPlan(
      name: 'Push Pull Legs',
      createdAt: now,
      updatedAt: now,
    )..id = 1;

    for (var i = 0; i < days; i++) {
      final day = WorkoutDay(label: 'Giorno ${i + 1}', sortOrder: i)
        ..id = i + 1;
      final block = Block.ofType(BlockType.standard, sortOrder: 0);
      block.exercises.add(
        Exercise(name: 'Panca piana', sets: 3, reps: '8', sortOrder: 0),
      );
      day.blocks.add(block);
      plan.days.add(day);
    }

    plans.add(plan);
    return plan;
  }

  WorkoutLog seedOpenSession(WorkoutPlan plan) =>
      logs.startSession(plan: plan, day: plan.days.first);

  Future<void> pumpDetail(
    WidgetTester tester, {
    required int planId,
    ImageShareService? shareService,
  }) async {
    await tester.pumpWidget(
      RepositoryProvider<ImageShareService>.value(
        value: shareService ?? sharer,
        child: MultiBlocProvider(
          providers: [
            BlocProvider<PlansCubit>(
              create: (context) => PlansCubit(repository: plans),
            ),
            BlocProvider<ActiveSessionCubit>(
              create: (context) => ActiveSessionCubit(repository: logs),
            ),
          ],
          child: MaterialApp.router(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            // I test verificano le stringhe italiane: senza fissare la lingua
            // la locale di test (en_US) non è fra quelle tradotte e Flutter
            // ripiegherebbe sulla prima in ordine alfabetico, il tedesco.
            locale: const Locale('it'),
            routerConfig: GoRouter(
              initialLocation: '/plans/$planId',
              routes: [
                GoRoute(
                  path: '/plans/:id',
                  builder: (context, state) => PlanDetailPage(
                    planId: int.parse(state.pathParameters['id']!),
                  ),
                ),
                GoRoute(
                  path: '/workout/new',
                  builder: (context, state) => Scaffold(
                    body: Text(
                      'NUOVA SESSIONE ${state.uri.queryParameters['dayId']}',
                    ),
                  ),
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
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('senza sessioni aperte si va dritti nell\'allenamento', (
    tester,
  ) async {
    seedPlan();
    await pumpDetail(tester, planId: 1);

    await tester.tap(find.text('Inizia allenamento'));
    await tester.pumpAndSettle();

    expect(find.text('NUOVA SESSIONE 1'), findsOneWidget);
  });

  testWidgets('con una sessione aperta si deve prima decidere che farne', (
    tester,
  ) async {
    seedOpenSession(seedPlan());
    await pumpDetail(tester, planId: 1);

    await tester.tap(find.text('Inizia allenamento'));
    await tester.pumpAndSettle();

    expect(find.text('C\'è già un allenamento in corso'), findsOneWidget);
    expect(find.text('Riprendi quello in corso'), findsOneWidget);
    expect(find.text('Chiudi e inizia il nuovo'), findsOneWidget);
    // Il bivio è comparso *prima* di aprire qualsiasi sessione.
    expect(find.textContaining('NUOVA SESSIONE'), findsNothing);
  });

  testWidgets('dal bivio si può tornare nella sessione in corso', (
    tester,
  ) async {
    final open = seedOpenSession(seedPlan());
    await pumpDetail(tester, planId: 1);

    await tester.tap(find.text('Inizia allenamento'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Riprendi quello in corso'));
    await tester.pumpAndSettle();

    expect(find.text('SESSIONE ${open.id}'), findsOneWidget);
  });

  testWidgets('dal bivio si può chiudere la precedente e iniziare la nuova', (
    tester,
  ) async {
    seedOpenSession(seedPlan());
    await pumpDetail(tester, planId: 1);

    await tester.tap(find.text('Inizia allenamento'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chiudi e inizia il nuovo'));
    await tester.pumpAndSettle();

    expect(find.text('NUOVA SESSIONE 1'), findsOneWidget);
  });

  testWidgets('chiudendo il pannello non si apre e non si chiude niente', (
    tester,
  ) async {
    final open = seedOpenSession(seedPlan());
    await pumpDetail(tester, planId: 1);

    await tester.tap(find.text('Inizia allenamento'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Chiudi'));
    await tester.pumpAndSettle();

    expect(find.text('Push Pull Legs'), findsOneWidget);
    expect(find.textContaining('SESSIONE'), findsNothing);
    // La sessione di prima è ancora aperta: rinunciare non chiude niente.
    expect(logs.getById(open.id)?.status, WorkoutStatus.inProgress);
  });

  testWidgets(
    'su una scheda multi-giorno il bivio viene prima della scelta del giorno',
    (tester) async {
      seedOpenSession(seedPlan(days: 2));
      await pumpDetail(tester, planId: 1);

      await tester.tap(find.text('Inizia allenamento'));
      await tester.pumpAndSettle();
      expect(find.text('C\'è già un allenamento in corso'), findsOneWidget);
      expect(find.text('Scegli il giorno'), findsNothing);

      await tester.tap(find.text('Chiudi e inizia il nuovo'));
      await tester.pumpAndSettle();
      expect(find.text('Scegli il giorno'), findsOneWidget);

      // "Giorno 2" è anche l'intestazione della sezione nella pagina sotto:
      // si tocca quello dentro al pannello.
      await tester.tap(
        find.descendant(
          of: find.byType(AppSheet),
          matching: find.text('Giorno 2'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('NUOVA SESSIONE 2'), findsOneWidget);
    },
  );

  testWidgets('"Condividi" manda in chat la scheda intera come immagine', (
    tester,
  ) async {
    seedPlan(days: 2);
    await pumpDetail(tester, planId: 1);

    await tester.tap(find.byTooltip('Mostra il menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Condividi'));
    await tester.pumpAndSettle();

    expect(sharer.shared, hasLength(1));
    final call = sharer.shared.single;
    expect(call.width, PlanShareImage.logicalWidth);
    // Quello che viene disegnato è il manifesto della scheda aperta, non uno
    // scatto della pagina.
    expect(call.widget, isA<PlanShareImage>());
    expect((call.widget as PlanShareImage).plan.id, 1);
    // Il nome del file è quello della scheda, ridotto a caratteri innocui.
    expect(call.fileName, 'push-pull-legs.png');
    expect(call.text, 'Push Pull Legs');
    // Ancora del popover per iPad: senza, il foglio compare dove capita.
    expect(call.originRect, isNotNull);
  });

  testWidgets('se l\'immagine non si crea, l\'utente lo viene a sapere', (
    tester,
  ) async {
    seedPlan();
    await pumpDetail(
      tester,
      planId: 1,
      shareService: RecordingImageShareService(fails: true),
    );

    await tester.tap(find.byTooltip('Mostra il menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Condividi'));
    await tester.pumpAndSettle();

    expect(
      find.text('Non è stato possibile creare l\'immagine della scheda.'),
      findsOneWidget,
    );
  });
}
