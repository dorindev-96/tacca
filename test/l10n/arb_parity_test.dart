import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Le traduzioni non hanno un compilatore che le controlli: una chiave che
/// manca in `app_de.arb` non rompe la build, a runtime ricade sull'italiano e
/// il tedesco resta con una frase in italiano in mezzo. Questi test sono
/// l'unico posto in cui quella dimenticanza fa rumore.
void main() {
  const templateLocale = 'it';

  /// Le traduzioni si scoprono dai file, non da un elenco scritto a mano:
  /// un elenco a mano dimentica esattamente la lingua appena aggiunta, che è
  /// l'unica che questo test avrebbe dovuto controllare.
  final translatedLocales =
      Directory('lib/l10n')
          .listSync()
          .map((e) => RegExp(r'app_(\w+)\.arb$').firstMatch(e.path)?.group(1))
          .whereType<String>()
          .where((locale) => locale != templateLocale)
          .toList()
        ..sort();

  Map<String, dynamic> readArb(String locale) =>
      jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
          as Map<String, dynamic>;

  List<String> keysOf(Map<String, dynamic> arb) =>
      arb.keys.where((k) => !k.startsWith('@')).toList();

  /// Nomi dei placeholder ICU: `{name}` e la testa di `{count, plural, …}`.
  Set<String> placeholdersOf(String message) => RegExp(
    r'\{(\w+)[,}]',
  ).allMatches(message).map((m) => m.group(1)!).toSet();

  final template = readArb(templateLocale);
  final templateKeys = keysOf(template);

  test('il template dichiara le chiavi che il resto dei test verifica', () {
    expect(templateKeys, isNotEmpty);
    expect(template['@@locale'], templateLocale);
    // Se la scoperta dei file si rompe, i gruppi qui sotto sparirebbero in
    // silenzio e il test passerebbe senza controllare niente.
    expect(translatedLocales, isNotEmpty);
  });

  for (final locale in translatedLocales) {
    group('app_$locale.arb', () {
      final arb = readArb(locale);

      test('dichiara la propria locale', () {
        expect(arb['@@locale'], locale);
      });

      test('ha esattamente le chiavi del template, nello stesso ordine', () {
        // L'ordine non è estetica: è quello che rende i file confrontabili
        // riga per riga quando si aggiunge una chiave.
        expect(keysOf(arb), templateKeys);
      });

      test('usa gli stessi placeholder del template', () {
        for (final key in templateKeys) {
          expect(
            placeholdersOf(arb[key] as String),
            placeholdersOf(template[key] as String),
            reason: 'placeholder diversi per "$key"',
          );
        }
      });

      test('tiene il plurale dove il template ce l\'ha', () {
        for (final key in templateKeys) {
          expect(
            (arb[key] as String).contains('plural'),
            (template[key] as String).contains('plural'),
            reason: 'forma plurale incoerente per "$key"',
          );
        }
      });

      test('non lascia nessuna traduzione vuota', () {
        for (final key in templateKeys) {
          expect(
            (arb[key] as String).trim(),
            isNotEmpty,
            reason: 'traduzione vuota per "$key"',
          );
        }
      });
    });
  }
}
