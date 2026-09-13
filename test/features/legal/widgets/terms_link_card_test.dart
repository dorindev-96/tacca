import 'package:tacca/core/constants.dart';
import 'package:tacca/features/legal/widgets/legal_notice_body.dart';
import 'package:tacca/l10n/app_localizations.dart';
import 'package:tacca/services/clipboard/clipboard_service.dart';
import 'package:tacca/services/links/link_opener.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fakes.dart';

// La riga dei termini esce dall'app (browser di sistema, nessuna WebView) e,
// se nessun browser risponde, il link finisce negli appunti invece di
// sparire.
void main() {
  late RecordingClipboardService clipboard;

  setUp(() => clipboard = RecordingClipboardService());

  Future<void> pumpCard(WidgetTester tester, LinkOpener opener) async {
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<LinkOpener>.value(value: opener),
          RepositoryProvider<ClipboardService>.value(value: clipboard),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          // I test verificano le stringhe italiane: senza fissare la lingua
          // la locale di test (en_US) non è fra quelle tradotte e Flutter
          // ripiegherebbe sulla prima in ordine alfabetico, il tedesco.
          locale: const Locale('it'),
          home: const Scaffold(body: TermsLinkCard()),
        ),
      ),
    );
  }

  testWidgets('apre i termini fuori dall app', (tester) async {
    final opener = FakeLinkOpener();
    await pumpCard(tester, opener);

    await tester.tap(find.text('Termini e condizioni'));
    await tester.pumpAndSettle();

    expect(opener.opened, [Uri.parse(AppConstants.termsUrl)]);
    expect(clipboard.written, isEmpty);
  });

  testWidgets('senza browser copia il link negli appunti', (tester) async {
    await pumpCard(tester, FakeLinkOpener(succeeds: false));

    await tester.tap(find.text('Termini e condizioni'));
    await tester.pumpAndSettle();

    expect(clipboard.last, AppConstants.termsUrl);
    expect(
      find.text('Nessun browser disponibile: link copiato negli appunti.'),
      findsOneWidget,
    );

    // Lascia scadere lo snack bar: un timer ancora pendente farebbe fallire
    // il test alla chiusura.
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });
}
