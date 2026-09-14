import 'package:flutter/material.dart';

import 'app_chrome.dart';
import 'app_palette.dart';
import 'app_typography.dart';

/// Come una pagina raggiunge i token del tema in cui si trova.
///
/// Prima del tema scuro i token erano costanti statiche e si leggevano per
/// nome (`AppColors.ink`). Ora sono due insiemi, e quale valga lo sa solo
/// l'albero: `context.colors.ink` è inchiostro scuro dentro il tema chiaro e
/// quasi bianco dentro quello scuro, senza che la pagina se ne accorga. È
/// l'unico modo in cui una card resta *una* card invece di diventare due.
///
/// La chiave è la luminosità del tema, non una preferenza letta altrove: chi
/// avvolge un sottoalbero in un `Theme` diverso — l'immagine da condividere lo
/// fa, fuori dall'albero dell'app — ottiene i token di *quel* tema, che è
/// esattamente quello che serve.
///
/// Le misure (`AppRadius`, `AppSpacing`) restano costanti statiche e si
/// importano come sempre: un raggio non cambia col tema, e passare anche
/// quelle dal contesto renderebbe più difficile capire cosa dipende davvero
/// dalla luminosità.
extension AppThemeContext on BuildContext {
  Brightness get _brightness => Theme.of(this).brightness;

  /// I colori del tema corrente.
  AppPalette get colors => AppPalette.of(_brightness);

  /// Gli stili di testo del tema corrente, colori inclusi.
  AppTypography get type => AppTypography.of(_brightness);

  /// Ombre dei livelli flottanti e stile delle barre di sistema.
  AppChrome get chrome => AppChrome.of(_brightness);
}
