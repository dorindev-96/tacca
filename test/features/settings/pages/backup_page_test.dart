import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:tacca/features/settings/cubit/backup_cubit.dart';
import 'package:tacca/features/settings/pages/backup_page.dart';
import 'package:tacca/l10n/app_localizations.dart';
import 'package:tacca/services/backup/backup_format.dart';

import '../../../support/fakes.dart';

/// Impostazioni → Backup: esportare è un tocco, ripristinare chiede prima
/// conferma dicendo che cosa arriva e che cosa se ne va.
void main() {
  setUpAll(() => initializeDateFormatting('it'));

  late FakeBackupService service;
  late FakeBackupFiles files;

  setUp(() {
    service = FakeBackupService(
      counts: (plans: 2, logs: 5),
      preview: fakeBackupPreview(
        plans: 3,
        logs: 1,
        createdAt: DateTime(2026, 10, 5, 18, 30),
      ),
    );
    files = FakeBackupFiles(picked: '/tmp/tacca-backup.tacca');
  });

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      BlocProvider(
        create: (context) => BackupCubit(backup: service, files: files),
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('it'),
          home: const BackupPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// I pulsanti stanno in fondo a una lista: prima di toccarli li si porta
  /// sullo schermo, come farebbe un dito.
  Future<void> tapButton(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets('spiega cosa c\'è nel backup e cosa no', (tester) async {
    await pumpPage(tester);

    expect(find.textContaining('tutte le tue schede'), findsOneWidget);
    // Le key non escono mai dal telefono, e la pagina lo dice.
    expect(find.textContaining('API key'), findsOneWidget);
  });

  testWidgets('esportare consegna il file al foglio di condivisione', (
    tester,
  ) async {
    await pumpPage(tester);

    await tapButton(tester, 'Esporta backup');

    expect(files.shared, hasLength(1));
    // Ancora del popover per iPad.
    expect(files.origins.single, isNotNull);
  });

  testWidgets('prima di ripristinare chiede conferma con i conti', (
    tester,
  ) async {
    await pumpPage(tester);

    await tapButton(tester, 'Scegli un backup');

    expect(find.text('Ripristinare questo backup?'), findsOneWidget);
    expect(
      find.text(
        'Backup del 5 ott 2026 alle 18:30: 3 schede e 1 allenamento. '
        'Prenderà il posto di tutto ciò che c\'è adesso nell\'app (2 schede '
        'e 5 allenamenti) e non si potrà tornare indietro.',
      ),
      findsOneWidget,
    );
    // Finché non si conferma non cambia niente.
    expect(service.restored, isEmpty);

    // "Ripristina" è anche l'etichetta della sezione sotto il dialog.
    await tester.tap(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('Ripristina'),
      ),
    );
    await tester.pumpAndSettle();

    expect(service.restored, [service.preview]);
    expect(
      find.text('Backup ripristinato: 3 schede e 1 allenamento.'),
      findsOneWidget,
    );
  });

  testWidgets('un backup vuoto lo dice senza sgrammaticare', (tester) async {
    service
      ..counts = (plans: 0, logs: 0)
      ..preview = fakeBackupPreview(plans: 0, logs: 0);
    await pumpPage(tester);

    await tapButton(tester, 'Scegli un backup');

    expect(
      find.textContaining(
        ': nessuna scheda e nessun allenamento. Prenderà il posto',
      ),
      findsOneWidget,
    );
  });

  testWidgets('mentre ripristina l\'app resta ferma, e poi torna', (
    tester,
  ) async {
    service.restoreGate = Completer<void>();
    await pumpPage(tester);

    await tapButton(tester, 'Scegli un backup');
    await tester.tap(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('Ripristina'),
      ),
    );
    // Il cerchio gira finché il ripristino non finisce: niente
    // pumpAndSettle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Ripristino in corso…'), findsOneWidget);
    // Né il tasto indietro né un tocco fuori lo chiudono.
    await tester.binding.handlePopRoute();
    await tester.tapAt(const Offset(10, 10));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Ripristino in corso…'), findsOneWidget);

    service.restoreGate!.complete();
    await tester.pumpAndSettle();

    expect(find.text('Ripristino in corso…'), findsNothing);
    expect(
      find.text('Backup ripristinato: 3 schede e 1 allenamento.'),
      findsOneWidget,
    );
  });

  testWidgets('annullando non si ripristina niente e non resta niente', (
    tester,
  ) async {
    await pumpPage(tester);

    await tapButton(tester, 'Scegli un backup');
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();

    expect(service.restored, isEmpty);
    expect(service.discarded, [service.preview]);
  });

  testWidgets('un file che non è un backup lo dice, senza chiedere niente', (
    tester,
  ) async {
    service.inspectProblem = BackupProblem.notABackup;
    await pumpPage(tester);

    await tapButton(tester, 'Scegli un backup');

    expect(find.text('Ripristinare questo backup?'), findsNothing);
    expect(find.text('Questo file non è un backup di Tacca.'), findsOneWidget);
  });

  testWidgets('se l\'export non riesce, l\'utente lo viene a sapere', (
    tester,
  ) async {
    service.exportFails = true;
    await pumpPage(tester);

    await tapButton(tester, 'Esporta backup');

    expect(
      find.text('Non è stato possibile creare il backup.'),
      findsOneWidget,
    );
  });
}
