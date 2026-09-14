import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'app_palette.dart';

/// Ciò che sta *sopra* la pagina: ombre dei livelli flottanti e aspetto delle
/// barre di sistema.
///
/// Nel restyling l'ombra è un'eccezione, non un livello di profondità
/// generico: le card non ne hanno, e ce l'hanno solo le superfici che
/// compaiono davanti al contenuto (menu contestuali, tab bar flottante).
///
/// Dipende dal tema per due motivi diversi. Le barre di sistema, perché le
/// icone del telefono devono essere scure su fondo chiaro e chiare su fondo
/// scuro — è l'unico punto in cui sbagliare tema rende illeggibile qualcosa
/// che non è nostro. L'ombra, perché un'ombra nera su un fondo quasi nero non
/// si vede: al buio va più coprente, ed è comunque un aiuto secondario, dato
/// che lì un livello flottante si stacca soprattutto perché è più chiaro di
/// quello che copre.
final class AppChrome {
  const AppChrome._({required this.floating, required this.systemOverlay});

  /// Il colore della barra di navigazione è quello del fondo pagina, preso da
  /// [palette] invece di riscritto: sono lo stesso colore, e ricopiarlo qui
  /// vorrebbe dire scoprire a schermo che uno dei due è rimasto indietro.
  factory AppChrome._of({
    required AppPalette palette,
    required Brightness brightness,
    required List<BoxShadow> floating,
  }) {
    final dark = brightness == Brightness.dark;
    return AppChrome._(
      floating: floating,
      systemOverlay: SystemUiOverlayStyle(
        statusBarColor: const Color(0x00000000),
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: dark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: palette.background,
        systemNavigationBarIconBrightness: dark
            ? Brightness.light
            : Brightness.dark,
      ),
    );
  }

  /// L'ombra dei livelli flottanti.
  final List<BoxShadow> floating;

  /// Barra di stato trasparente e barra di navigazione al colore del fondo,
  /// con le icone nel verso giusto per il tema.
  final SystemUiOverlayStyle systemOverlay;

  /// Chiaro: l'ombra del file di design,
  /// `0 8px 24px rgba(0,0,0,.15), 0 2px 6px rgba(0,0,0,.06)`.
  static final AppChrome light = AppChrome._of(
    palette: AppPalette.light,
    brightness: Brightness.light,
    floating: const [
      BoxShadow(color: Color(0x26000000), blurRadius: 24, offset: Offset(0, 8)),
      BoxShadow(color: Color(0x0F000000), blurRadius: 6, offset: Offset(0, 2)),
    ],
  );

  /// Scuro: la stessa forma d'ombra, più opaca perché il fondo sotto è già
  /// scuro e un nero al 15% sopra un nero non disegna niente.
  static final AppChrome dark = AppChrome._of(
    palette: AppPalette.dark,
    brightness: Brightness.dark,
    floating: const [
      BoxShadow(color: Color(0x80000000), blurRadius: 24, offset: Offset(0, 8)),
      BoxShadow(color: Color(0x40000000), blurRadius: 6, offset: Offset(0, 2)),
    ],
  );

  static AppChrome of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;
}
