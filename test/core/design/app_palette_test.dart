import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tacca/app/theme.dart';
import 'package:tacca/core/design/app_chrome.dart';
import 'package:tacca/core/design/app_palette.dart';
import 'package:tacca/core/design/app_typography.dart';

/// Luminanza relativa (WCAG 2.1).
double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

/// Rapporto di contrasto fra due colori opachi.
double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Gli stili di una tipografia per nome, per poterli confrontare a coppie.
Map<String, TextStyle> _styles(AppTypography t) => {
  'screenTitle': t.screenTitle,
  'sheetTitle': t.sheetTitle,
  'sheetTitleLong': t.sheetTitleLong,
  'subtitle': t.subtitle,
  'cardTitle': t.cardTitle,
  'button': t.button,
  'buttonSmall': t.buttonSmall,
  'blockType': t.blockType,
  'row': t.row,
  'rowStrong': t.rowStrong,
  'sectionLabel': t.sectionLabel,
  'meta': t.meta,
  'metaStrong': t.metaStrong,
  'chip': t.chip,
  'chipStrong': t.chipStrong,
  'clock': t.clock,
  'numeric': t.numeric,
  'numericField': t.numericField,
  'paragraph': t.paragraph,
  'paragraphSmall': t.paragraphSmall,
  'caption': t.caption,
};

void main() {
  group('AppPalette', () {
    test('la luminosità scelta decide la palette, e sono due sole', () {
      expect(AppPalette.of(Brightness.light), same(AppPalette.light));
      expect(AppPalette.of(Brightness.dark), same(AppPalette.dark));
    });

    test('lime e rosa non si capovolgono, e nemmeno ciò che ci sta sopra', () {
      // È la regola che il tema scuro poteva rompere in silenzio: se `onLime`
      // seguisse il tema, al buio sarebbe testo quasi bianco su lime.
      expect(AppPalette.dark.lime, AppPalette.light.lime);
      expect(AppPalette.dark.onLime, AppPalette.light.onLime);
      expect(AppPalette.dark.onLimeSurface, AppPalette.light.onLimeSurface);
      expect(AppPalette.dark.danger, AppPalette.light.danger);
      expect(AppPalette.dark.onDanger, AppPalette.light.onDanger);
    });

    test('al buio il testo si schiarisce ma il blocco pieno resta scuro', () {
      final dark = AppPalette.dark;
      // Se `inkSurface` si schiarisse come `ink`, il lime che tab bar e barra
      // del timer si portano dentro non si distinguerebbe più dal fondo.
      expect(_luminance(dark.ink), greaterThan(0.5));
      expect(_luminance(dark.inkSurface), lessThan(0.2));
      expect(_contrast(dark.lime, dark.inkSurface), greaterThan(4.5));
    });

    test('la pagina è più scura delle card, che sono più scure del blocco', () {
      final dark = AppPalette.dark;
      expect(
        _luminance(dark.background),
        lessThan(_luminance(dark.surface)),
        reason: 'una card deve galleggiare *sopra* il fondo anche al buio',
      );
      expect(_luminance(dark.surface), lessThan(_luminance(dark.inkSurface)));
      // L'incavo mostra il fondo, come nel tema chiaro.
      expect(dark.fill, dark.background);
      expect(AppPalette.light.fill, AppPalette.light.background);
    });

    test('al buio ogni testo passa AA sul fondo su cui sta', () {
      final c = AppPalette.dark;
      final pairs = <String, (Color, Color)>{
        'ink su fondo': (c.ink, c.background),
        'ink su card': (c.ink, c.surface),
        'prosa su card': (c.body, c.surface),
        'secondario su fondo': (c.muted, c.background),
        'secondario su card': (c.muted, c.surface),
        'secondario nell\'incavo': (c.muted, c.fill),
        'testo sul blocco pieno': (c.onInkSurface, c.inkSurface),
        'rosa su card': (c.danger, c.surface),
        'rosa sul suo velo': (c.danger, c.dangerSurface),
        'inchiostro sul lime': (c.onLime, c.lime),
        'inchiostro sul rosa': (c.onDanger, c.danger),
      };
      for (final entry in pairs.entries) {
        final (fg, bg) = entry.value;
        expect(
          _contrast(fg, bg),
          greaterThanOrEqualTo(4.5),
          reason: '${entry.key} è sotto AA (RNF-04)',
        );
      }
    });
  });

  group('AppTypography', () {
    test('le due tipografie differiscono solo nei colori', () {
      // Una misura diversa fra chiaro e scuro sarebbe un bug, non una scelta:
      // è la ragione per cui le basi stanno scritte una volta sola.
      const sentinel = Color(0xFF00FF00);
      final light = _styles(AppTypography.light);
      final dark = _styles(AppTypography.dark);

      expect(dark.keys, light.keys);
      for (final name in light.keys) {
        expect(
          dark[name]!.copyWith(color: sentinel),
          light[name]!.copyWith(color: sentinel),
          reason: 'le misure di "$name" non coincidono fra i due temi',
        );
      }
    });

    test('ogni stile porta il colore del suo ruolo', () {
      expect(AppTypography.dark.row.color, AppPalette.dark.ink);
      expect(AppTypography.dark.meta.color, AppPalette.dark.muted);
      expect(AppTypography.dark.paragraph.color, AppPalette.dark.body);
      // Le cifre del timer stanno sulla barra piena, non sul fondo pagina.
      expect(AppTypography.dark.clock.color, AppPalette.dark.onInkSurface);
      expect(AppTypography.light.clock.color, AppPalette.light.onInkSurface);
    });
  });

  group('AppTheme', () {
    test('i due ThemeData si costruiscono una volta sola', () {
      // `MaterialApp` li rilegge a ogni cambio di lingua o tema.
      expect(AppTheme.light, same(AppTheme.light));
      expect(AppTheme.of(Brightness.dark), same(AppTheme.dark));
    });

    test('ogni tema porta la sua palette dove i widget la cercano', () {
      expect(AppTheme.dark.brightness, Brightness.dark);
      expect(AppTheme.dark.scaffoldBackgroundColor, AppPalette.dark.background);
      expect(AppTheme.dark.cardTheme.color, AppPalette.dark.surface);
      expect(
        AppTheme.light.scaffoldBackgroundColor,
        AppPalette.light.background,
      );
    });

    test('il cursore segue il testo, non `primary`', () {
      // Senza questo, al buio il cursore sarebbe grigio scuro su fondo scuro.
      expect(AppTheme.dark.textSelectionTheme.cursorColor, AppPalette.dark.ink);
      expect(AppTheme.dark.colorScheme.primary, AppPalette.dark.inkSurface);
    });
  });

  group('AppChrome', () {
    test('le icone di sistema si invertono col tema', () {
      expect(
        AppChrome.dark.systemOverlay.statusBarIconBrightness,
        Brightness.light,
      );
      expect(
        AppChrome.light.systemOverlay.statusBarIconBrightness,
        Brightness.dark,
      );
    });

    test('la barra di navigazione prende il fondo dalla palette', () {
      expect(
        AppChrome.dark.systemOverlay.systemNavigationBarColor,
        AppPalette.dark.background,
      );
      expect(
        AppChrome.light.systemOverlay.systemNavigationBarColor,
        AppPalette.light.background,
      );
    });
  });
}
