import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tacca/app/theme.dart';
import 'package:tacca/core/design/app_palette.dart';
import 'package:tacca/core/design/theme_context.dart';
import 'package:tacca/core/widgets/app_sheet.dart';
import 'package:tacca/features/settings/cubit/locale_cubit.dart';
import 'package:tacca/features/settings/cubit/theme_mode_cubit.dart';
import 'package:tacca/features/settings/pages/settings_page.dart';
import 'package:tacca/l10n/app_localizations.dart';

import '../../../support/fakes.dart';

void main() {
  /// La pagina dentro un `MaterialApp` che prende lingua *e* tema dai cubit,
  /// come fa `App` in produzione: è l'unico modo di verificare che scegliere
  /// una lingua o un tema ridisegni davvero l'interfaccia, e non solo lo stato.
  Future<void> pumpSettings(
    WidgetTester tester, {
    required FakeSettingsRepository settings,
  }) async {
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<LocaleCubit>(
            create: (context) => LocaleCubit(settings: settings),
          ),
          BlocProvider<ThemeModeCubit>(
            create: (context) => ThemeModeCubit(settings: settings),
          ),
        ],
        child: Builder(
          builder: (context) => MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: context.watch<LocaleCubit>().state ?? const Locale('it'),
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: context.watch<ThemeModeCubit>().state,
            home: const SettingsPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Il sottotitolo della riga [title].
  ///
  /// Da quando le righe che possono seguire il sistema sono due (lingua e
  /// tema), "Come il sistema" compare due volte in questa pagina: un
  /// `find.text` nudo non direbbe più di quale riga sta parlando.
  Finder subtitleOf(String title, String subtitle) => find.descendant(
    of: find.ancestor(
      of: find.text(title),
      matching: find.byType(SettingsTile),
    ),
    matching: find.text(subtitle),
  );

  /// Una voce *dentro* il pannello aperto, non la riga che gli sta sotto con
  /// la stessa etichetta.
  Finder inSheet(String label) =>
      find.descendant(of: find.byType(AppSheet), matching: find.text(label));

  /// Il tema in cui la pagina si sta disegnando davvero, non lo stato del
  /// cubit: è la differenza fra "la preferenza è cambiata" e "l'app è
  /// cambiata".
  ThemeData shownTheme(WidgetTester tester) =>
      Theme.of(tester.element(find.byType(SettingsPage)));

  testWidgets('senza scelta le righe dicono che si segue il sistema', (
    tester,
  ) async {
    await pumpSettings(tester, settings: FakeSettingsRepository());

    expect(find.text('Lingua'), findsOneWidget);
    expect(subtitleOf('Lingua', 'Come il sistema'), findsOneWidget);
    expect(find.text('Tema'), findsOneWidget);
    expect(subtitleOf('Tema', 'Come il sistema'), findsOneWidget);
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

    await tester.tap(inSheet('Svenska'));
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
    await tester.tap(inSheet('Comme le système'));
    await tester.pumpAndSettle();

    expect(settings.localeCode, isNull);
    // Tornata al ripiego dei test (italiano), non rimasta in francese.
    expect(find.text('Lingua'), findsOneWidget);
  });

  testWidgets('un tema salvato compare nella riga', (tester) async {
    await pumpSettings(
      tester,
      settings: FakeSettingsRepository(themeModeName: 'dark'),
    );

    expect(subtitleOf('Tema', 'Scuro'), findsOneWidget);
    // La riga lo dice *e* l'app è davvero scura.
    expect(shownTheme(tester).brightness, Brightness.dark);
  });

  testWidgets('scegliere il tema scuro ridipinge l\'app e salva la '
      'preferenza', (tester) async {
    final settings = FakeSettingsRepository();
    await pumpSettings(tester, settings: settings);
    expect(shownTheme(tester).brightness, Brightness.light);

    await tester.tap(find.text('Tema'));
    await tester.pumpAndSettle();
    expect(inSheet('Chiaro'), findsOneWidget);
    expect(inSheet('Scuro'), findsOneWidget);

    await tester.tap(inSheet('Scuro'));
    await tester.pumpAndSettle();

    expect(settings.themeModeName, 'dark');
    // Non è cambiata solo la riga: il fondo della pagina è quello scuro, e i
    // token che le pagine leggono dal contesto sono quelli dell'altra palette.
    final theme = shownTheme(tester);
    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, AppPalette.dark.background);
    expect(
      tester.element(find.byType(SettingsPage)).colors,
      same(AppPalette.dark),
    );
  });

  testWidgets('anche il tema può tornare a seguire il sistema', (tester) async {
    final settings = FakeSettingsRepository(themeModeName: 'dark');
    await pumpSettings(tester, settings: settings);

    await tester.tap(find.text('Tema'));
    await tester.pumpAndSettle();
    await tester.tap(inSheet('Come il sistema'));
    await tester.pumpAndSettle();

    // `null` e non "system": nello storage "mai scelto" è l'assenza della
    // chiave, come per la lingua.
    expect(settings.themeModeName, isNull);
    // I test girano con un sistema chiaro, quindi si torna al chiaro.
    expect(shownTheme(tester).brightness, Brightness.light);
  });
}
