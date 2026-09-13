import 'package:tacca/data/entities/log_entry.dart';
import 'package:tacca/data/entities/workout_log.dart';
import 'package:tacca/features/history/cubit/history_cubit.dart';
import 'package:tacca/features/history/pages/history_page.dart';
import 'package:tacca/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../../../support/fakes.dart';

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  late FakeWorkoutLogRepository repository;

  setUp(() => repository = FakeWorkoutLogRepository());
  tearDown(() => repository.dispose());

  WorkoutLog finishedLog({
    required String planName,
    required DateTime startedAt,
    String dayLabel = 'Giorno A',
    int sets = 0,
  }) {
    final log = WorkoutLog(
      startedAt: startedAt,
      finishedAt: startedAt.add(const Duration(minutes: 50)),
      dbStatus: WorkoutStatus.completed.name,
      planNameSnapshot: planName,
      dayLabelSnapshot: dayLabel,
    );
    final entry = LogEntry(exerciseNameSnapshot: 'Panca piana');
    for (var i = 1; i <= sets; i++) {
      entry.sets.add(buildLogSet(i, weightKg: 80, reps: '8'));
    }
    log.entries.add(entry);
    return log;
  }

  Future<void> pumpHistory(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp.router(
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
                create: (context) => HistoryCubit(repository: repository),
                child: const HistoryPage(),
              ),
            ),
            GoRoute(
              path: '/history/:logId',
              builder: (context, state) => Scaffold(
                body: Text('DETTAGLIO ${state.pathParameters['logId']}'),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('stato vuoto senza allenamenti registrati', (tester) async {
    await pumpHistory(tester);

    expect(find.text('Nessun allenamento registrato.'), findsOneWidget);
  });

  testWidgets('elenca le sessioni con durata e serie registrate', (
    tester,
  ) async {
    repository.saveLog(
      finishedLog(
        planName: 'Upper / Lower',
        startedAt: DateTime(2026, 8, 14, 18),
        sets: 3,
      ),
    );
    await pumpHistory(tester);

    expect(find.text('Upper / Lower'), findsOneWidget);
    expect(find.textContaining('Giorno A'), findsOneWidget);
    expect(find.textContaining('50m'), findsOneWidget);
    expect(find.textContaining('3 serie'), findsOneWidget);
  });

  testWidgets('il filtro per scheda restringe l\'elenco', (tester) async {
    repository
      ..saveLog(
        finishedLog(
          planName: 'Upper / Lower',
          startedAt: DateTime(2026, 8, 14, 18),
        ),
      )
      ..saveLog(
        finishedLog(
          planName: 'Full Body',
          startedAt: DateTime(2026, 8, 10, 18),
        ),
      );
    await pumpHistory(tester);

    expect(find.text('Upper / Lower'), findsOneWidget);
    expect(find.text('Full Body'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Full Body').last);
    await tester.pumpAndSettle();

    expect(find.text('Upper / Lower'), findsNothing);
    expect(find.text('Full Body'), findsWidgets);
  });

  testWidgets('aprire una sessione porta al dettaglio', (tester) async {
    final id = repository.saveLog(
      finishedLog(
        planName: 'Upper / Lower',
        startedAt: DateTime(2026, 8, 14, 18),
      ),
    );
    await pumpHistory(tester);

    await tester.tap(find.text('Upper / Lower'));
    await tester.pumpAndSettle();

    expect(find.text('DETTAGLIO $id'), findsOneWidget);
  });

  testWidgets('eliminare una sessione richiede conferma', (tester) async {
    repository.saveLog(
      finishedLog(
        planName: 'Upper / Lower',
        startedAt: DateTime(2026, 8, 14, 18),
      ),
    );
    await pumpHistory(tester);

    await tester.tap(find.byTooltip('Elimina'));
    await tester.pumpAndSettle();
    expect(find.text('Eliminare la sessione?'), findsOneWidget);

    // Annullando non si elimina nulla.
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
    expect(find.text('Upper / Lower'), findsOneWidget);

    await tester.tap(find.byTooltip('Elimina'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(Dialog), matching: find.text('Elimina')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nessun allenamento registrato.'), findsOneWidget);
  });
}
