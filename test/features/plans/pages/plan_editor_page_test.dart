import 'package:tacca/data/entities/workout_plan.dart';
import 'package:tacca/data/repositories/plan_repository.dart';
import 'package:tacca/features/plans/cubit/plan_editor_cubit.dart';
import 'package:tacca/features/plans/cubit/plan_editor_labels.dart';
import 'package:tacca/features/plans/pages/plan_editor_page.dart';
import 'package:tacca/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockPlanRepository extends Mock implements PlanRepository {}

void main() {
  late _MockPlanRepository repository;

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

  Future<void> pumpEditor(WidgetTester tester) async {
    // La pagina è più alta della viewport di test di default: senza uno
    // spazio grande a sufficienza i tap su elementi in fondo alla lista
    // (es. "Aggiungi esercizio" dopo aver espanso un blocco) mancano il
    // bersaglio perché fuori dall'area visibile.
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // I test verificano le stringhe italiane: senza fissare la lingua
        // la locale di test (en_US) non è fra quelle tradotte e Flutter
        // ripiegherebbe sulla prima in ordine alfabetico, il tedesco.
        locale: const Locale('it'),
        home: BlocProvider(
          create: (context) => PlanEditorCubit.create(
            repository: repository,
            labels: editorLabels,
          ),
          child: const PlanEditorPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'la scheda a giorno singolo non mostra i tab; aggiungere un giorno li mostra',
    (tester) async {
      await pumpEditor(tester);

      // Giorno singolo implicito: nessun tab, solo il pulsante "Aggiungi giorno".
      expect(find.text('Aggiungi giorno'), findsOneWidget);
      expect(find.text('Giorno unico'), findsNothing);

      await tester.tap(find.text('Aggiungi giorno'));
      await tester.pumpAndSettle();

      // Da 2 giorni in su, i tab (con le etichette) diventano visibili.
      expect(find.text('Giorno unico'), findsOneWidget);
      expect(find.text('Giorno B'), findsOneWidget);
    },
  );

  testWidgets(
    'aggiungere un blocco EMOM mostra i suoi parametri; aggiungere un esercizio mostra il campo nome',
    (tester) async {
      await pumpEditor(tester);

      await tester.tap(find.text('Aggiungi blocco'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('EMOM'));
      await tester.pumpAndSettle();

      // Il blocco parte compresso: va espanso per vedere i parametri.
      await tester.tap(find.text('EMOM'));
      await tester.pumpAndSettle();

      expect(find.text('Intervallo (s)'), findsOneWidget);
      expect(find.text('Durata totale (min)'), findsOneWidget);
      // Parametri di un altro tipo (Tabata) non devono comparire.
      expect(find.text('Lavoro (s)'), findsNothing);

      await tester.tap(find.text('Aggiungi esercizio'));
      await tester.pumpAndSettle();

      expect(find.text('Esercizio'), findsOneWidget);
    },
  );

  testWidgets('cambiare il tipo di blocco sostituisce i parametri mostrati', (
    tester,
  ) async {
    await pumpEditor(tester);

    await tester.tap(find.text('Aggiungi blocco'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('EMOM'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('EMOM')); // espandi la card
    await tester.pumpAndSettle();

    expect(find.text('Intervallo (s)'), findsOneWidget);

    await tester.tap(
      find.byWidgetPredicate((w) => w is DropdownButtonFormField),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tabata').last);
    await tester.pumpAndSettle();

    expect(find.text('Intervallo (s)'), findsNothing);
    expect(find.text('Durata totale (min)'), findsNothing);
    expect(find.text('Lavoro (s)'), findsOneWidget);
    expect(find.text('Recupero (s)'), findsOneWidget);
    expect(find.text('Round'), findsOneWidget);
  });

  testWidgets('il blocco testo libero non mostra la sezione esercizi', (
    tester,
  ) async {
    await pumpEditor(tester);

    await tester.tap(find.text('Aggiungi blocco'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Testo libero'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Testo libero').first); // espandi la card
    await tester.pumpAndSettle();

    expect(find.text('Contenuto'), findsOneWidget);
    expect(find.text('Aggiungi esercizio'), findsNothing);
  });

  testWidgets(
    'salvare senza nome mostra un errore e non chiama il repository',
    (tester) async {
      await pumpEditor(tester);

      await tester.tap(find.text('Salva'));
      await tester.pumpAndSettle();

      expect(find.text('Il nome della scheda è obbligatorio.'), findsOneWidget);
      verifyNever(() => repository.savePlan(any()));
    },
  );

  testWidgets(
    'la creazione manuale non mostra l\'avviso di contenuto generato dall\'AI',
    (tester) async {
      await pumpEditor(tester);

      expect(find.textContaining('Contenuto generato dall\'AI'), findsNothing);
    },
  );

  testWidgets(
    'la revisione di una bozza AI mostra l\'avviso di contenuto generato dall\'AI',
    (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final draft = WorkoutPlan(
        name: 'Scheda importata',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          // I test verificano le stringhe italiane: senza fissare la lingua
          // la locale di test (en_US) non è fra quelle tradotte e Flutter
          // ripiegherebbe sulla prima in ordine alfabetico, il tedesco.
          locale: const Locale('it'),
          home: BlocProvider(
            create: (context) => PlanEditorCubit.draft(
              repository: repository,
              labels: editorLabels,
              draft: draft,
            ),
            child: const PlanEditorPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Contenuto generato dall\'AI'),
        findsOneWidget,
      );
    },
  );
}
