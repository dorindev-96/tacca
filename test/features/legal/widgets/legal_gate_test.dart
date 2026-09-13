import 'package:tacca/core/constants.dart';
import 'package:tacca/features/legal/cubit/legal_notice_cubit.dart';
import 'package:tacca/features/legal/widgets/legal_gate.dart';
import 'package:tacca/l10n/app_localizations.dart';
import 'package:tacca/services/clipboard/clipboard_service.dart';
import 'package:tacca/services/links/link_opener.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fakes.dart';

// Il cancello legale: finché la manleva non è accettata, le schermate
// dell'app dietro non vengono nemmeno costruite.
void main() {
  late FakeSettingsRepository settings;

  setUp(() => settings = FakeSettingsRepository());

  Future<void> pumpGate(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<LinkOpener>.value(value: FakeLinkOpener()),
          RepositoryProvider<ClipboardService>.value(
            value: RecordingClipboardService(),
          ),
        ],
        child: BlocProvider(
          create: (context) => LegalNoticeCubit(settings: settings),
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            // I test verificano le stringhe italiane: senza fissare la lingua
            // la locale di test (en_US) non è fra quelle tradotte e Flutter
            // ripiegherebbe sulla prima in ordine alfabetico, il tedesco.
            locale: const Locale('it'),
            home: const LegalGate(child: Text('contenuto')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('al primo avvio mostra la manleva', (tester) async {
    await pumpGate(tester);

    expect(find.text('Prima di iniziare'), findsOneWidget);
    expect(find.text("Non è un'app medica"), findsOneWidget);
    expect(find.text('contenuto'), findsNothing);
  });

  testWidgets('accettando si entra e la scelta resta', (tester) async {
    await pumpGate(tester);

    await tester.tap(find.text('Accetto e continuo'));
    await tester.pumpAndSettle();

    expect(find.text('contenuto'), findsOneWidget);
    expect(find.text('Prima di iniziare'), findsNothing);
    expect(
      settings.acceptedLegalNoticeVersion,
      AppConstants.legalNoticeVersion,
    );
  });

  testWidgets('chi ha già accettato non rivede niente', (tester) async {
    settings.acceptedLegalNoticeVersion = AppConstants.legalNoticeVersion;

    await pumpGate(tester);

    expect(find.text('contenuto'), findsOneWidget);
    expect(find.text('Prima di iniziare'), findsNothing);
  });
}
