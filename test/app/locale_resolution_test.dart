import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tacca/app/app.dart';
import 'package:tacca/core/constants.dart';
import 'package:tacca/l10n/app_localizations.dart';

void main() {
  final supported = AppLocalizations.supportedLocales;

  test('la lista generata è in ordine alfabetico: il ripiego di Flutter '
      'sarebbe il tedesco, ed è il motivo per cui resolveLocale esiste', () {
    expect(supported.first.languageCode, 'de');
    expect(supported.map((l) => l.languageCode), contains('it'));
  });

  test('sceglie la lingua del telefono quando è fra quelle tradotte', () {
    for (final code in ['it', 'de', 'es', 'fr', 'sv']) {
      expect(App.resolveLocale([Locale(code)], supported).languageCode, code);
    }
  });

  test('ignora il paese: de_AT legge app_de.arb', () {
    expect(
      App.resolveLocale([const Locale('de', 'AT')], supported).languageCode,
      'de',
    );
  });

  test('ripiega sull\'italiano, non sulla prima della lista, quando la '
      'lingua del telefono non è tradotta', () {
    expect(
      App.resolveLocale([const Locale('ja')], supported),
      AppConstants.fallbackLocale,
    );
    expect(
      App.resolveLocale([const Locale('en', 'US')], supported),
      AppConstants.fallbackLocale,
    );
    expect(App.resolveLocale(null, supported), AppConstants.fallbackLocale);
    expect(App.resolveLocale([], supported), AppConstants.fallbackLocale);
  });

  test('rispetta l\'ordine di preferenza del telefono', () {
    // Prima lingua non tradotta, seconda sì: vince la seconda, non il ripiego.
    expect(
      App.resolveLocale([
        const Locale('ja'),
        const Locale('sv'),
        const Locale('de'),
      ], supported).languageCode,
      'sv',
    );
  });
}
