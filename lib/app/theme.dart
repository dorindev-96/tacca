import 'package:flutter/material.dart';

import '../core/design/app_chrome.dart';
import '../core/design/app_palette.dart';
import '../core/design/app_radius.dart';
import '../core/design/app_spacing.dart';
import '../core/design/app_typography.dart';

/// Tema dell'app: il restyling sul linguaggio visivo del file Figma
/// "Gym full figma" — un solo accento lime `#BBF246`, superfici a raggio 26,
/// niente ombre sulle card.
///
/// Qui vive **tutto** ciò che deve restare identico ovunque: colori, raggi,
/// altezze minime dei controlli, stile di card, campi, sheet e menu. Le
/// pagine non ridefiniscono questi valori — così una card dell'archivio e una
/// della sessione sono la stessa card.
///
/// **Due temi, un solo impaginato.** [light] è la palette disegnata; [dark] è
/// la stessa, letta al buio (vedi [AppPalette]). Non sono due interfacce: sono
/// lo stesso albero di component theme costruito due volte da [_build], perché
/// una differenza fra i due che non sia un colore sarebbe un bug. Qualunque
/// cosa si aggiunga qui nasce quindi dentro [_build] e prende i valori da
/// `palette`/`type`, mai da un esadecimale scritto sul posto.
///
/// Nota tecnica: gli stili dei component theme vanno costruiti da
/// [AppTypography] e mai ripresi da `ThemeData(...).textTheme`, perché
/// `ThemeData` fonde le *dimensioni* tipografiche solo dentro `textTheme`
/// (uno stile preso da lì arriverebbe senza `fontSize`).
abstract final class AppTheme {
  /// Area minima dei controlli tappabili: l'app si usa in palestra, spesso
  /// con una mano sola e senza guardare (RNF-04).
  static const Size _minTapSize = Size(64, 48);

  /// Il tema chiaro: i valori del file di design.
  ///
  /// `final` e non un getter: `MaterialApp` si ricostruisce a ogni cambio di
  /// lingua o di tema e rileggerebbe entrambi, ricostruendo ogni volta tutti i
  /// component theme.
  static final ThemeData light = _build(Brightness.light);

  /// Il tema scuro.
  static final ThemeData dark = _build(Brightness.dark);

  /// Il tema di una luminosità. Serve a chi disegna **fuori** dall'albero
  /// dell'app e deve portarsi il tema addosso: l'immagine da condividere.
  static ThemeData of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  static ThemeData _build(Brightness brightness) {
    final palette = AppPalette.of(brightness);
    final type = AppTypography.of(brightness);
    final chrome = AppChrome.of(brightness);

    // `primary` è la superficie che spicca, non il colore del testo: il
    // cursore e la selezione dei campi se li prende `textSelectionTheme` qui
    // sotto, altrimenti al buio il cursore sarebbe grigio scuro su fondo
    // scuro. Le coppie `on*` del lime e del rosa passano da `onLime`/
    // `onDanger` perché quei due colori non si capovolgono col tema.
    final scheme = ColorScheme(
      brightness: brightness,
      primary: palette.inkSurface,
      onPrimary: palette.onInkSurface,
      primaryContainer: palette.lime,
      onPrimaryContainer: palette.onLime,
      secondary: palette.lime,
      onSecondary: palette.onLime,
      secondaryContainer: palette.lime,
      onSecondaryContainer: palette.onLime,
      tertiary: palette.inkSurface,
      onTertiary: palette.onInkSurface,
      tertiaryContainer: palette.lime,
      onTertiaryContainer: palette.onLime,
      error: palette.danger,
      onError: palette.onDanger,
      errorContainer: palette.dangerSurface,
      onErrorContainer: palette.danger,
      surface: palette.background,
      onSurface: palette.ink,
      onSurfaceVariant: palette.muted,
      surfaceContainerLowest: palette.surface,
      surfaceContainerLow: palette.surface,
      surfaceContainer: palette.surface,
      surfaceContainerHigh: palette.fill,
      surfaceContainerHighest: palette.fill,
      outline: palette.stroke,
      outlineVariant: palette.stroke,
      inverseSurface: palette.inkSurface,
      onInverseSurface: palette.onInkSurface,
      inversePrimary: palette.lime,
      shadow: const Color(0xFF000000),
      scrim: palette.scrim,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      textTheme: _textTheme(type),
      scaffoldBackgroundColor: palette.background,
      canvasColor: palette.surface,
      splashFactory: InkSparkle.splashFactory,
      iconTheme: IconThemeData(color: palette.ink, size: 24),

      // Cursore e selezione seguono il *testo*, non `primary`: sono l'unico
      // punto in cui la differenza si vedrebbe subito.
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: palette.ink,
        selectionHandleColor: palette.ink,
        selectionColor: palette.ink.withValues(alpha: 0.24),
      ),

      // Le pagine disegnano la propria intestazione (pulsanti icona quadrati
      // + titolo Lato Black nel corpo): l'AppBar resta configurata per le
      // poche schermate di servizio che la usano ancora.
      appBarTheme: AppBarThemeData(
        backgroundColor: palette.background,
        foregroundColor: palette.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: 64,
        titleTextStyle: type.screenTitle,
        iconTheme: IconThemeData(color: palette.ink),
        actionsIconTheme: IconThemeData(color: palette.ink),
        systemOverlayStyle: chrome.systemOverlay,
      ),

      // La forma dell'app: superficie piena, raggio 26, senza bordo e senza
      // ombra. Si stacca dal fondo per luminosità, non per contorno.
      cardTheme: CardThemeData(
        elevation: 0,
        color: palette.surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),

      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.card,
          vertical: AppSpacing.xs,
        ),
        minVerticalPadding: AppSpacing.md,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        iconColor: palette.muted,
        titleTextStyle: type.row,
        subtitleTextStyle: type.paragraphSmall,
      ),

      // Campi pieni, senza contorno: il contorno lo fa il colore della
      // superficie. Il focus è l'unico stato che disegna un bordo.
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: palette.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.card,
          vertical: AppSpacing.lg,
        ),
        border: _fieldBorder(Colors.transparent),
        enabledBorder: _fieldBorder(Colors.transparent),
        disabledBorder: _fieldBorder(Colors.transparent),
        focusedBorder: _fieldBorder(palette.ink, width: 1.5),
        errorBorder: _fieldBorder(palette.danger),
        focusedErrorBorder: _fieldBorder(palette.danger, width: 1.5),
        labelStyle: type.sectionLabel,
        floatingLabelStyle: type.meta,
        hintStyle: type.row.copyWith(color: palette.muted),
        helperStyle: type.meta,
        errorStyle: type.meta.copyWith(color: palette.danger),
        prefixIconColor: palette.muted,
        suffixIconColor: palette.muted,
      ),

      // Pillola piena: l'azione principale di ogni schermata.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: palette.inkSurface,
          foregroundColor: palette.onInkSurface,
          disabledBackgroundColor: palette.stroke,
          disabledForegroundColor: palette.muted,
          minimumSize: _minTapSize,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          elevation: 0,
          shape: const StadiumBorder(),
          textStyle: type.button,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.ink,
          minimumSize: _minTapSize,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.card),
          side: BorderSide(color: palette.stroke),
          shape: const StadiumBorder(),
          textStyle: type.button,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: palette.ink,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          shape: const StadiumBorder(),
          textStyle: type.buttonSmall,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: palette.ink,
          minimumSize: const Size.square(44),
          shape: const CircleBorder(),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: palette.fill,
        selectedColor: palette.lime,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
        labelStyle: type.chip,
        secondaryLabelStyle: type.chipStrong,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        iconTheme: IconThemeData(color: palette.muted, size: 16),
      ),

      // I pannelli modali coprono la pagina: raggio 24 in alto e chiusura
      // con la X in testata (niente maniglia — nel design non c'è).
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.surface,
        modalBackgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: palette.scrim,
        showDragHandle: false,
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.sheet),
          ),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        barrierColor: palette.scrim,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        insetPadding: const EdgeInsets.all(AppSpacing.xl),
        titleTextStyle: type.sheetTitle,
        contentTextStyle: type.paragraph,
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: palette.surface,
        surfaceTintColor: Colors.transparent,
        // La stessa ombra dei livelli flottanti, che al buio è più coprente:
        // il menu è uno di quelli.
        shadowColor: chrome.floating.first.color,
        elevation: 8,
        menuPadding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        textStyle: type.row,
      ),

      // Il margine in basso è quello del dock più alto (pillola + tab bar
      // flottante), non 24 fissi: l'overlay dello snackbar è unico per tutta
      // l'app e non sa quale pagina lo mostra, quindi deve restare sopra la
      // pillola più bassa che esiste piuttosto che finirci sopra.
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: palette.inkSurface,
        contentTextStyle: type.paragraph.copyWith(color: palette.onInkSurface),
        actionTextColor: palette.lime,
        insetPadding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.dockClearance,
        ),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),

      // Dentro una card la tile espandibile non deve disegnare le proprie
      // linee di separazione: il contenitore è già la card.
      expansionTileTheme: ExpansionTileThemeData(
        shape: const RoundedRectangleBorder(side: BorderSide.none),
        collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
        tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        childrenPadding: EdgeInsets.zero,
        iconColor: palette.ink,
        collapsedIconColor: palette.muted,
        backgroundColor: palette.surface,
        collapsedBackgroundColor: palette.surface,
      ),

      dividerTheme: DividerThemeData(
        color: palette.stroke,
        thickness: 1,
        space: AppSpacing.xl,
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: palette.ink,
        linearTrackColor: palette.stroke,
        circularTrackColor: Colors.transparent,
        linearMinHeight: 4,
      ),
    );
  }

  static OutlineInputBorder _fieldBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  /// I ruoli Material mappati sui token del design. Le pagine usano
  /// `context.type` direttamente; questo serve ai widget di framework che
  /// pescano dal `TextTheme` (dialog, snackbar, `ListTile`, `DropdownMenu`).
  static TextTheme _textTheme(AppTypography type) => TextTheme(
    displayLarge: type.clock,
    displayMedium: type.clock,
    displaySmall: type.clock,
    headlineLarge: type.screenTitle,
    headlineMedium: type.screenTitle,
    headlineSmall: type.sheetTitleLong,
    titleLarge: type.subtitle,
    titleMedium: type.cardTitle,
    titleSmall: type.blockType,
    bodyLarge: type.row,
    bodyMedium: type.paragraph,
    bodySmall: type.paragraphSmall,
    labelLarge: type.button,
    labelMedium: type.meta,
    labelSmall: type.chip,
  );
}
