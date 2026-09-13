import 'package:flutter/widgets.dart';

/// Costanti applicative condivise.
abstract final class AppConstants {
  /// Lingua usata quando quella del telefono non è fra quelle tradotte.
  ///
  /// L'elenco delle lingue supportate non sta qui: lo genera `gen-l10n` dai
  /// file `lib/l10n/app_<lingua>.arb` (`AppLocalizations.supportedLocales`),
  /// così aggiungere una traduzione è aggiungere un file. Quell'elenco però è
  /// in ordine alfabetico, e il ripiego di default di Flutter è il primo
  /// elemento: senza questa costante un telefono in giapponese finirebbe in
  /// tedesco. Vedi `App.build`.
  static const Locale fallbackLocale = Locale('it');

  /// Termini e condizioni completi. Si aprono nel browser di sistema
  /// (`LinkOpener`): l'app non incorpora nessuna WebView.
  static const String termsUrl =
      'https://tverdohleb.dev/apps/tacca/terminiecondizioni.html';

  /// Versione dell'informativa mostrata al primo avvio (`LegalNoticeCubit`).
  ///
  /// Quello che viene salvato non è un booleano ma questo numero: alzarlo di
  /// uno quando cambia la sostanza dei termini rimette l'avviso davanti anche
  /// a chi aveva già accettato la versione precedente.
  static const int legalNoticeVersion = 1;
}
