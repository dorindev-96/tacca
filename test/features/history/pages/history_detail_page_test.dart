import 'package:tacca/data/entities/log_entry.dart';
import 'package:tacca/data/entities/workout_log.dart';
import 'package:tacca/features/history/cubit/history_detail_cubit.dart';
import 'package:tacca/features/history/pages/history_detail_page.dart';
import 'package:tacca/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../../../support/fakes.dart';

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  late FakeWorkoutLogRepository repository;

  setUp(() => repository = FakeWorkoutLogRepository());
  tearDown(() => repository.dispose());

  int seedLog() {
    final log = WorkoutLog(
      startedAt: DateTime(2026, 8, 14, 18),
      finishedAt: DateTime(2026, 8, 14, 19, 5),
      dbStatus: WorkoutStatus.completed.name,
      planNameSnapshot: 'Upper / Lower',
      dayLabelSnapshot: 'Giorno A',
      notes: 'Spalla destra un po\' rigida',
    );

    final panca = LogEntry(exerciseNameSnapshot: 'Panca piana', sortOrder: 0);
    panca.sets.addAll([
      buildLogSet(1, weightKg: 80, reps: '8'),
      buildLogSet(2, weightKg: 82.5, reps: '6'),
    ]);
    // Esercizio previsto ma non svolto: deve restare visibile.
    final rematore = LogEntry(exerciseNameSnapshot: 'Rematore', sortOrder: 1);

    log.entries.addAll([panca, rematore]);
    return repository.saveLog(log);
  }

  Future<void> pumpDetail(WidgetTester tester, int logId) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // I test verificano le stringhe italiane: senza fissare la lingua
        // la locale di test (en_US) non è fra quelle tradotte e Flutter
        // ripiegherebbe sulla prima in ordine alfabetico, il tedesco.
        locale: const Locale('it'),
        home: BlocProvider(
          create: (context) =>
              HistoryDetailCubit(repository: repository, logId: logId),
          child: const HistoryDetailPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('mostra esercizi, serie, carichi e note della sessione', (
    tester,
  ) async {
    await pumpDetail(tester, seedLog());

    expect(find.text('Upper / Lower'), findsOneWidget);
    expect(find.textContaining('Giorno A'), findsOneWidget);
    expect(find.textContaining('Completata'), findsOneWidget);
    expect(find.text('Spalla destra un po\' rigida'), findsOneWidget);

    expect(find.text('Panca piana'), findsOneWidget);
    expect(find.text('80 kg × 8'), findsOneWidget);
    expect(find.text('82.5 kg × 6'), findsOneWidget);

    expect(find.text('Rematore'), findsOneWidget);
    expect(find.text('Non svolto'), findsOneWidget);
  });

  testWidgets('una sessione inesistente non fa esplodere la pagina', (
    tester,
  ) async {
    await pumpDetail(tester, 404);

    expect(find.text('Sessione non trovata.'), findsOneWidget);
  });
}
