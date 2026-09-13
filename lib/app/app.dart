import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/constants.dart';
import '../features/legal/widgets/legal_gate.dart';
import '../l10n/app_localizations.dart';
import 'router.dart';
import 'theme.dart';

/// Widget radice: configura `MaterialApp.router`, tema e localizzazione.
class App extends StatefulWidget {
  const App({super.key});

  /// Sceglie la lingua fra quelle tradotte, con l'italiano come ripiego.
  ///
  /// Il criterio è la sola lingua, perché gli ARB sono per lingua e non per
  /// paese: un telefono in `de_AT` deve leggere `app_de.arb`. Serve solo per
  /// il ripiego finale — quello di Flutter è il primo elemento di una lista
  /// in ordine alfabetico, cioè il tedesco, che nessuno ha scelto.
  @visibleForTesting
  static Locale resolveLocale(
    List<Locale>? preferred,
    Iterable<Locale> supported,
  ) {
    for (final locale in preferred ?? const <Locale>[]) {
      for (final candidate in supported) {
        if (candidate.languageCode == locale.languageCode) return candidate;
      }
    }
    return AppConstants.fallbackLocale;
  }

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  late final GoRouter _router = createRouter();

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: kDebugMode,
      // Un tema solo: il restyling ha una palette sola (vedi AppTheme). Il
      // blocco su ThemeMode.light serve a non mostrare, su un telefono in
      // dark mode, un'interfaccia che nessuno ha disegnato.
      theme: AppTheme.theme,
      themeMode: ThemeMode.light,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      localeListResolutionCallback: App.resolveLocale,
      routerConfig: _router,
      // La manleva del primo avvio sta *sopra* al router: finché non è
      // accettata, `child` (cioè tutte le schermate) non viene montato.
      builder: (context, child) => LegalGate(child: child!),
    );
  }
}
