import 'package:tacca/features/ai_import/cubit/ai_paste_import_cubit.dart';
import 'package:tacca/features/ai_import/pages/ai_paste_import_page.dart';
import 'package:tacca/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../support/fakes.dart';

const _validResponse = '''
Ecco la tua scheda:
```json
{
  "name": "Full body",
  "days": [
    {
      "label": "Giorno 1",
      "blocks": [
        { "type": "standard", "exercises": [{ "name": "Panca piana" }] }
      ]
    }
  ]
}
```
''';

void main() {
  late RecordingClipboardService clipboard;

  setUp(() => clipboard = RecordingClipboardService());

  Future<void> pumpPage(WidgetTester tester) async {
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
                create: (context) => AiPasteImportCubit(
                  imageInput: FakeImageInput(),
                  imageStore: FakeImageStore(),
                  ocr: FakeOcrService(),
                  clipboard: clipboard,
                ),
                child: const AiPasteImportPage(),
              ),
            ),
            GoRoute(
              path: '/plans/new/review',
              builder: (context, state) =>
                  const Scaffold(body: Text('REVISIONE')),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> goToPaste(
    WidgetTester tester, {
    String text = 'Panca 10x4',
  }) async {
    await tester.enterText(find.byKey(const ValueKey('paste-text')), text);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copia il prompt e continua'));
    await tester.pumpAndSettle();
    // La conferma di copia è una snackbar, e finché resta a schermo copre la
    // pillola in fondo: la si lascia scadere prima di toccare il passo 2.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  testWidgets('il primo passo copia il prompt e porta al secondo', (
    tester,
  ) async {
    await pumpPage(tester);

    expect(find.text('Prepara il messaggio'), findsOneWidget);
    expect(find.text('Passo 1 di 2'), findsOneWidget);

    await goToPaste(tester);

    expect(clipboard.last, contains('Panca 10x4'));
    expect(find.text('Incolla la risposta'), findsOneWidget);
    expect(find.text('Passo 2 di 2'), findsOneWidget);
  });

  testWidgets('senza testo la pillola non parte', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.text('Copia il prompt e continua'));
    await tester.pumpAndSettle();

    expect(clipboard.written, isEmpty);
    expect(find.text('Prepara il messaggio'), findsOneWidget);
  });

  testWidgets('una risposta valida apre la revisione', (tester) async {
    await pumpPage(tester);
    await goToPaste(tester);

    await tester.enterText(
      find.byKey(const ValueKey('paste-response')),
      _validResponse,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fine'));
    await tester.pumpAndSettle();

    expect(find.text('REVISIONE'), findsOneWidget);
  });

  testWidgets('una risposta inutilizzabile offre correzione e testo libero '
      '(RNF-05)', (tester) async {
    await pumpPage(tester);
    await goToPaste(tester);

    await tester.enterText(
      find.byKey(const ValueKey('paste-response')),
      'Non ci sono riuscito, scusa.',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fine'));
    await tester.pumpAndSettle();

    expect(find.text('REVISIONE'), findsNothing);
    expect(find.text('Copia il messaggio di correzione'), findsOneWidget);

    // L'uscita di sicurezza tiene comunque quello che l'utente ha in mano.
    await tester.tap(find.text('Tieni come testo libero'));
    await tester.pumpAndSettle();

    expect(find.text('REVISIONE'), findsOneWidget);
  });

  testWidgets('dal secondo passo si torna al primo senza perdere il testo', (
    tester,
  ) async {
    await pumpPage(tester);
    await goToPaste(tester);

    await tester.tap(find.byTooltip('Indietro'));
    await tester.pumpAndSettle();

    expect(find.text('Prepara il messaggio'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('paste-text')))
          .controller!
          .text,
      'Panca 10x4',
    );
  });
}
