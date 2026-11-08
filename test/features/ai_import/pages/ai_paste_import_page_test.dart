import 'package:tacca/features/ai_import/cubit/ai_paste_import_cubit.dart';
import 'package:tacca/features/ai_import/cubit/shared_text_cubit.dart';
import 'package:tacca/features/ai_import/pages/ai_paste_import_page.dart';
import 'package:tacca/l10n/app_localizations.dart';
import 'package:tacca/services/share/text_share_service.dart';
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
  late RecordingTextShareService share;
  late RecordingClipboardService clipboard;
  late FakeSharedTextReceiver receiver;
  late SharedTextCubit sharedText;

  setUp(() {
    share = RecordingTextShareService();
    clipboard = RecordingClipboardService();
    receiver = FakeSharedTextReceiver();
    sharedText = SharedTextCubit(receiver: receiver);
  });

  tearDown(() => sharedText.close());

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      BlocProvider<SharedTextCubit>.value(
        value: sharedText,
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
                  create: (context) => AiPasteImportCubit(
                    imageInput: FakeImageInput(),
                    imageStore: FakeImageStore(),
                    ocr: FakeOcrService(),
                    share: share,
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
    await tester.tap(find.text('Condividi il prompt e continua'));
    await tester.pumpAndSettle();
  }

  testWidgets('il primo passo manda il prompt al foglio di condivisione e '
      'porta al secondo', (tester) async {
    await pumpPage(tester);

    expect(find.text('Prepara il messaggio'), findsOneWidget);
    expect(find.text('Passo 1 di 2'), findsOneWidget);

    await goToPaste(tester);

    expect(share.last, contains('Panca 10x4'));
    expect(clipboard.written, isEmpty);
    expect(find.text('Incolla la risposta'), findsOneWidget);
    expect(find.text('Passo 2 di 2'), findsOneWidget);
    // Dal secondo passo si può rimandare o copiare.
    expect(find.text('Condividi di nuovo'), findsOneWidget);
    expect(find.text('Copia il prompt'), findsOneWidget);
  });

  testWidgets('senza testo la pillola non parte', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.text('Condividi il prompt e continua'));
    await tester.pumpAndSettle();

    expect(share.shared, isEmpty);
    expect(find.text('Prepara il messaggio'), findsOneWidget);
  });

  testWidgets('se il foglio si chiude senza scegliere si resta al primo '
      'passo, senza avvisi', (tester) async {
    share.outcome = TextShareOutcome.dismissed;
    await pumpPage(tester);

    await goToPaste(tester);

    expect(find.text('Prepara il messaggio'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('senza foglio di condivisione il prompt va negli appunti e la '
      'pagina lo dice', (tester) async {
    share.outcome = TextShareOutcome.unavailable;
    await pumpPage(tester);

    await goToPaste(tester);

    expect(find.text('Incolla la risposta'), findsOneWidget);
    expect(clipboard.last, contains('Panca 10x4'));
    expect(
      find.text(
        'Il foglio di condivisione non è disponibile: il testo è negli '
        'appunti, incollalo nella chat.',
      ),
      findsOneWidget,
    );
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
    // Le uscite stanno sotto il banner dell'errore: nella finestra di test
    // di default finirebbero sotto la pillola agganciata in fondo, che si
    // prenderebbe il tocco. Si alza la finestra.
    tester.view.physicalSize = const Size(2400, 4200);
    addTearDown(tester.view.reset);
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
    expect(find.text('Condividi il messaggio di correzione'), findsOneWidget);
    expect(find.text('Copia il messaggio di correzione'), findsOneWidget);

    await tester.tap(find.text('Condividi il messaggio di correzione'));
    await tester.pumpAndSettle();
    expect(share.last, contains('cannot be used'));

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

  testWidgets('la risposta condivisa con l\'app mentre si aspetta arriva da '
      'sola e apre la revisione', (tester) async {
    await pumpPage(tester);
    await goToPaste(tester);

    receiver.pending.add(_validResponse);
    await sharedText.drain();
    await tester.pumpAndSettle();

    expect(find.text('REVISIONE'), findsOneWidget);
    // Preso: non deve arrivare una seconda volta a chi apre dopo.
    expect(sharedText.state, isNull);
  });

  testWidgets('un testo già in attesa quando la pagina compare finisce nel '
      'passo giusto', (tester) async {
    // Senza JSON dentro è una scheda, non una risposta: va nel primo passo.
    receiver.pending.add('Panca 10x4\nSquat 10x4');
    await sharedText.drain();

    await pumpPage(tester);

    expect(find.text('Prepara il messaggio'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('paste-text')))
          .controller!
          .text,
      'Panca 10x4\nSquat 10x4',
    );
    expect(sharedText.state, isNull);
  });
}
