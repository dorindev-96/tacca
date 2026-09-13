import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tacca/features/settings/cubit/locale_cubit.dart';
import 'package:tacca/features/settings/pages/settings_page.dart';
import 'package:tacca/l10n/app_localizations.dart';

import '../../../support/fakes.dart';

void main() {
  /// La pagina dentro un `MaterialApp` che prende la lingua dal cubit, come
  /// fa `App` in produzione: è l'unico modo di verificare che scegliere una
  /// lingua ridisegni davvero l'interfaccia, e non solo lo stato.
  Future<void> pumpSettings(
    WidgetTester tester, {
    required FakeSettingsRepository settings,
  }) async {
    await tester.pumpWidget(
      BlocProvider<LocaleCubit>(
        create: (context) => LocaleCubit(settings: settings),
        child: BlocBuilder<LocaleCubit, Locale?>(
          builder: (context, locale) => MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: locale ?? const Locale('it'),
            home: const SettingsPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('senza scelta la riga dice che si segue il sistema', (
    tester,
  ) async {
    await pumpSettings(tester, settings: FakeSettingsRepository());

    expect(find.text('Lingua'), findsOneWidget);
    expect(find.text('Come il sistema'), findsOneWidget);
  });

  testWidgets('una lingua salvata compare nella riga, scritta nella sua '
      'lingua', (tester) async {
    await pumpSettings(
      tester,
      settings: FakeSettingsRepository(localeCode: 'de'),
    );

    // La riga si è già ridisegnata in tedesco, e il nome della lingua è
    // l'endonimo: "Deutsch", non "Tedesco".
    expect(find.text('Sprache'), findsOneWidget);
    expect(find.text('Deutsch'), findsOneWidget);
  });

  testWidgets('scegliere una lingua ridisegna l\'app e salva la preferenza', (
    tester,
  ) async {
    final settings = FakeSettingsRepository();
    await pumpSettings(tester, settings: settings);

    await tester.tap(find.text('Lingua'));
    await tester.pumpAndSettle();

    // Il pannello elenca le lingue con il loro nome, più "come il sistema".
    expect(find.text('Svenska'), findsOneWidget);
    expect(find.text('Français'), findsOneWidget);

    await tester.tap(find.text('Svenska'));
    await tester.pumpAndSettle();

    expect(settings.localeCode, 'sv');
    // Tutta la pagina è in svedese, non solo la riga toccata.
    expect(find.text('Språk'), findsOneWidget);
    expect(find.text('Inställningar'), findsOneWidget);
  });

  testWidgets('si può tornare a seguire il sistema', (tester) async {
    final settings = FakeSettingsRepository(localeCode: 'fr');
    await pumpSettings(tester, settings: settings);
    expect(find.text('Langue'), findsOneWidget);

    await tester.tap(find.text('Langue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Comme le système'));
    await tester.pumpAndSettle();

    expect(settings.localeCode, isNull);
    // Tornata al ripiego dei test (italiano), non rimasta in francese.
    expect(find.text('Lingua'), findsOneWidget);
  });
}
