import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../core/constants.dart';
import '../features/legal/widgets/legal_gate.dart';
import '../features/settings/cubit/locale_cubit.dart';
import '../features/settings/cubit/theme_mode_cubit.dart';
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
    // La lingua scelta a mano vince su quella del telefono; `null` — nessuna
    // scelta, o preferenza non ancora letta — la lascia decidere al sistema.
    // In entrambi i casi la parola finale è di `resolveLocale`, perché anche
    // una lingua scelta a mano passa da lì.
    final locale = context.watch<LocaleCubit>().state;

    // Come la lingua: `ThemeMode.system` — il default — lascia decidere al
    // telefono, e la scelta fatta a mano vince.
    final themeMode = context.watch<ThemeModeCubit>().state;

    return MaterialApp.router(
      locale: locale,
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: kDebugMode,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
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
