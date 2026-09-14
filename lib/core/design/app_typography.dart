import 'dart:ui' show Brightness;

import 'package:flutter/painting.dart';

import 'app_palette.dart';

/// Tipografia del restyling, nelle due luminosità.
///
/// Due caratteri con due ruoli distinti, mai mescolati dentro la stessa riga:
///
/// * **Lato** per tutta l'interfaccia — titoli, righe, pulsanti, numeri.
///   Serrata, con line-height quasi nullo: è ciò che dà alle schermate
///   l'aspetto "impaginato" invece che "elencato".
/// * **il carattere di sistema** (SF Pro su iOS, Roboto su Android) per i
///   paragrafi in prosa: descrizione della scheda, note, spiegazioni. Un
///   paragrafo lungo in Lato serrato non si legge.
///
/// I paragrafi si ottengono lasciando `fontFamily` a null: `TextTheme` non
/// eredita alcuna famiglia globale, perché [AppTheme] non imposta mai
/// `ThemeData.fontFamily`.
///
/// **Sui pesi.** Il design nomina Lato Medium (500) ed ExtraBold (800), che
/// però non esistono: la famiglia pubblicata ha 400/700/900. Sono quelli i
/// pesi che il canvas del design ha davvero renderizzato, e sono quelli che
/// stanno qui — scritti espliciti, così nessuno si chiede perché un "500"
/// arrivi regolare.
///
/// **Perché è una classe con istanze e non più costanti.** Ogni stile porta
/// addosso il suo colore, e il colore dipende dal tema. Le misure invece no:
/// un `fontSize` diverso fra chiaro e scuro sarebbe un bug, non una scelta.
/// Perciò le misure stanno una volta sola nelle basi private `_…` senza
/// colore, e [_of] le colora con i ruoli della palette. Le due istanze non
/// possono divergere nelle misure nemmeno per sbaglio, e l'elenco dentro [_of]
/// diventa la mappa leggibile di quale testo ha quale ruolo di colore.
///
/// Le pagine non la costruiscono: la leggono dal contesto (`context.type`, in
/// `theme_context.dart`).
final class AppTypography {
  const AppTypography._({
    required this.screenTitle,
    required this.sheetTitleLong,
    required this.subtitle,
    required this.cardTitle,
    required this.button,
    required this.buttonSmall,
    required this.blockType,
    required this.row,
    required this.rowStrong,
    required this.sectionLabel,
    required this.meta,
    required this.metaStrong,
    required this.chip,
    required this.chipStrong,
    required this.clock,
    required this.numeric,
    required this.numericField,
    required this.paragraph,
    required this.paragraphSmall,
    required this.caption,
  });

  /// Colora le misure con i ruoli di [palette]. È qui che si legge, in venti
  /// righe, quale testo è inchiostro e quale è secondario.
  factory AppTypography._of(AppPalette palette) => AppTypography._(
    screenTitle: _screenTitle.copyWith(color: palette.ink),
    sheetTitleLong: _sheetTitleLong.copyWith(color: palette.ink),
    subtitle: _subtitle.copyWith(color: palette.ink),
    cardTitle: _cardTitle.copyWith(color: palette.ink),
    button: _button.copyWith(color: palette.ink),
    buttonSmall: _buttonSmall.copyWith(color: palette.ink),
    blockType: _blockType.copyWith(color: palette.ink),
    row: _row.copyWith(color: palette.ink),
    rowStrong: _rowStrong.copyWith(color: palette.ink),
    sectionLabel: _sectionLabel.copyWith(color: palette.muted),
    meta: _meta.copyWith(color: palette.muted),
    metaStrong: _metaStrong.copyWith(color: palette.ink),
    chip: _chip.copyWith(color: palette.muted),
    chipStrong: _chipStrong.copyWith(color: palette.ink),
    // Le cifre del timer stanno sopra la barra piena, non sul fondo pagina:
    // il loro colore è quello del blocco, non l'inchiostro.
    clock: _clock.copyWith(color: palette.onInkSurface),
    numeric: _numeric.copyWith(color: palette.ink),
    numericField: _numericField.copyWith(color: palette.ink),
    paragraph: _paragraph.copyWith(color: palette.body),
    paragraphSmall: _paragraphSmall.copyWith(color: palette.muted),
    caption: _caption.copyWith(color: palette.muted),
  );

  static const String fontFamily = 'Lato';

  static const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

  /// Titolo di schermata ("Le mie schede", "Giorno A"). Lato Black 24.
  final TextStyle screenTitle;

  /// Titolo di un bottom sheet.
  TextStyle get sheetTitle => screenTitle;

  /// Titolo di sheet con testo lungo (nome esercizio + numero di serie).
  final TextStyle sheetTitleLong;

  /// Sottotitolo: giorno nel dettaglio scheda, nome dell'esercizio corrente.
  final TextStyle subtitle;

  /// Titolo di una card non in evidenza.
  final TextStyle cardTitle;

  /// Etichetta di un pulsante pillola.
  final TextStyle button;

  /// Etichetta di un pulsante compatto (alto 40–44).
  final TextStyle buttonSmall;

  /// Tipo di blocco ("Superset", "EMOM"): maiuscoletto tipografico ottenuto
  /// con la spaziatura, non con `toUpperCase()`.
  final TextStyle blockType;

  /// Riga di elenco, voce di menu, label di campo: il peso "corrente".
  final TextStyle row;

  /// Riga di elenco in evidenza (nome della scheda in uso).
  final TextStyle rowStrong;

  /// Label di sezione ("In uso", "Schede", "Archiviate", "Descrizione").
  final TextStyle sectionLabel;

  /// Dato secondario accanto a una riga ("3 giorni").
  final TextStyle meta;

  /// Come [meta], ma è un dato che va notato.
  final TextStyle metaStrong;

  /// Testo dentro una chip piccola.
  final TextStyle chip;

  /// Chip che porta un conteggio in corso ("2/4 serie").
  final TextStyle chipStrong;

  /// Cifre del timer: enormi, incolonnate, leggibili col telefono appoggiato
  /// a terra (RNF-04). Stanno sopra la barra piena, quindi il loro colore è
  /// [AppPalette.onInkSurface].
  final TextStyle clock;

  /// Valore numerico allineato a destra in una riga (carico × ripetizioni).
  final TextStyle numeric;

  /// Numero grande di un campo (peso e ripetizioni nel log rapido).
  final TextStyle numericField;

  /// Paragrafo in prosa. `fontFamily` volutamente nullo: è il carattere di
  /// sistema.
  final TextStyle paragraph;

  /// Paragrafo secondario (note di un blocco, sottotitolo di una riga).
  final TextStyle paragraphSmall;

  /// Riga di servizio sotto una card ("Ultima volta (12/08): …").
  final TextStyle caption;

  /// La tipografia del tema chiaro.
  static final AppTypography light = AppTypography._of(AppPalette.light);

  /// Quella del tema scuro: le stesse misure, i colori dell'altra palette.
  static final AppTypography dark = AppTypography._of(AppPalette.dark);

  static AppTypography of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  // ------------------------------------------------------- misure (Lato)

  static const TextStyle _screenTitle = TextStyle(
    fontFamily: fontFamily,
    fontSize: 24,
    height: 1.0,
    fontWeight: FontWeight.w900,
  );

  static const TextStyle _sheetTitleLong = TextStyle(
    fontFamily: fontFamily,
    fontSize: 22,
    height: 1.2,
    fontWeight: FontWeight.w900,
  );

  static const TextStyle _subtitle = TextStyle(
    fontFamily: fontFamily,
    fontSize: 18,
    height: 1.2,
    fontWeight: FontWeight.w900,
  );

  static const TextStyle _cardTitle = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    height: 1.2,
    fontWeight: FontWeight.w700,
  );

  static const TextStyle _button = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    height: 1.5,
    fontWeight: FontWeight.w700,
  );

  static const TextStyle _buttonSmall = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    height: 1.2,
    fontWeight: FontWeight.w700,
  );

  static const TextStyle _blockType = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    height: 1.2,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.6,
  );

  static const TextStyle _row = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    height: 1.2,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle _rowStrong = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    height: 1.2,
    fontWeight: FontWeight.w700,
  );

  static const TextStyle _sectionLabel = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    height: 1.2,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle _meta = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    height: 1.2,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle _metaStrong = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    height: 1.2,
    fontWeight: FontWeight.w700,
  );

  static const TextStyle _chip = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    height: 1.0,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle _chipStrong = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    height: 1.0,
    fontWeight: FontWeight.w700,
  );

  static const TextStyle _clock = TextStyle(
    fontFamily: fontFamily,
    fontSize: 44,
    height: 1.0,
    fontWeight: FontWeight.w900,
    fontFeatures: _tabular,
  );

  static const TextStyle _numeric = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    height: 1.2,
    fontWeight: FontWeight.w700,
    fontFeatures: _tabular,
  );

  static const TextStyle _numericField = TextStyle(
    fontFamily: fontFamily,
    fontSize: 22,
    height: 1.2,
    fontWeight: FontWeight.w900,
    fontFeatures: _tabular,
  );

  // ---------------------------------------- misure (carattere di sistema)

  static const TextStyle _paragraph = TextStyle(
    fontSize: 14,
    height: 1.5,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle _paragraphSmall = TextStyle(
    fontSize: 13,
    height: 1.5,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle _caption = TextStyle(
    fontSize: 12,
    height: 1.4,
    fontWeight: FontWeight.w400,
  );
}
