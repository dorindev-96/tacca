import 'package:flutter/widgets.dart';

/// Il nome di ogni lingua **nella lingua stessa** (endonimo).
///
/// Non sta negli ARB apposta, e non è una svista: "Deutsch" si scrive
/// "Deutsch" anche dentro un'interfaccia in italiano. Metterlo a tradurre
/// significherebbe ritrovarsi "Tedesco" nell'elenco italiano e "Alemán" in
/// quello spagnolo — cioè un elenco che chi cerca la propria lingua non sa
/// leggere, che è esattamente il momento in cui serve.
///
/// Va tenuto allineato a `AppLocalizations.supportedLocales`: aggiungere un
/// `app_<lingua>.arb` senza aggiungere qui il suo nome fa comparire nel
/// selettore il codice nudo. C'è un test che se ne accorge.
const Map<String, String> languageEndonyms = {
  'it': 'Italiano',
  'de': 'Deutsch',
  'es': 'Español',
  'fr': 'Français',
  'sv': 'Svenska',
};

/// Nome da mostrare per [locale]; ripiega sul codice se manca l'endonimo,
/// perché una riga con scritto "pt" resta scegliibile mentre una riga vuota
/// no.
String languageNameOf(Locale locale) =>
    languageEndonyms[locale.languageCode] ?? locale.languageCode;
