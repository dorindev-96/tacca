import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tacca/core/l10n/language_names.dart';
import 'package:tacca/l10n/app_localizations.dart';

void main() {
  test('ogni lingua tradotta ha il suo endonimo nel selettore', () {
    for (final locale in AppLocalizations.supportedLocales) {
      expect(
        languageEndonyms[locale.languageCode],
        isNotNull,
        reason:
            'manca il nome di "${locale.languageCode}" in languageEndonyms: '
            'nel selettore comparirebbe il codice nudo',
      );
    }
  });

  test('non avanzano endonimi di lingue che non esistono più', () {
    final supported = AppLocalizations.supportedLocales
        .map((l) => l.languageCode)
        .toSet();

    expect(languageEndonyms.keys, everyElement(isIn(supported)));
  });

  test(
    'un codice senza endonimo ripiega sul codice, non su una riga vuota',
    () {
      expect(languageNameOf(const Locale('pt')), 'pt');
    },
  );
}
