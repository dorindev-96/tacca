import 'dart:ui' show Brightness;

import 'package:flutter/painting.dart';

/// La palette dell'app, nelle sue **due** versioni.
///
/// Il linguaggio visivo viene dal file Figma "Gym full figma", che disegna il
/// tema chiaro: quelli sono i valori di [light], e non si toccano. [dark] non
/// è una seconda interfaccia inventata a mano — è lo *stesso* impaginato letto
/// al contrario, ruolo per ruolo: la pagina diventa la cosa più scura, le card
/// ci galleggiano sopra restando un gradino più chiare, l'inchiostro si
/// schiarisce. Il rapporto fra i ruoli è quello che resta uguale; i valori no.
///
/// Non ci sono colori sciolti: una pagina non scrive mai un esadecimale, e
/// nemmeno `AppPalette.light`. Legge [AppPalette] dal contesto
/// (`context.colors`, in `theme_context.dart`), così la stessa card è chiara o
/// scura senza saperlo.
///
/// ## I ruoli che si capovolgono male
///
/// Nel tema chiaro alcuni ruoli coincidono per caso, perché "il testo" e "la
/// superficie che spicca" sono entrambi `#192126`, e "una card" e "il testo
/// sopra il blocco pieno" entrambi `#FFFFFF`. Al buio si separano, e tenerli
/// distinti è tutto il lavoro di questo file:
///
/// * **[ink] contro [inkSurface]**: `ink` è il testo, e al buio diventa quasi
///   bianco; `inkSurface` è il blocco pieno (pillola dell'azione principale,
///   tab bar, barra del timer, snackbar) e al buio **resta scuro**, solo un
///   gradino sopra le card. Non può schiarirsi: tab bar e barra del timer si
///   portano dentro il lime, e il lime su fondo quasi bianco non si vede più
///   (1,1:1 — sparire, non spiccare).
/// * **[surface] contro [onInkSurface]**: nel chiaro il testo sopra il blocco
///   pieno è bianco come le card. Al buio le card sono scure e quel testo no.
/// * **lime e rosa non si capovolgono affatto**: sono già colori chiari, e
///   restano identici nei due temi. Quindi anche ciò che ci sta sopra deve
///   restare identico, e ha token suoi — [onLime], [onDanger],
///   [onLimeSurface] — invece di un commento che invita a stare attenti. Se il
///   testo su una pillola lime scrivesse `ink`, al buio sarebbe bianco su
///   lime: illeggibile. È l'unica regola del design che il tema scuro poteva
///   rompere in silenzio.
///
/// Regola non negoziabile, ora scritta nei tipi: **sopra il lime il testo è
/// [onLime]**, mai [ink].
final class AppPalette {
  const AppPalette({
    required this.background,
    required this.surface,
    required this.fill,
    required this.inkSurface,
    required this.onInkSurface,
    required this.ink,
    required this.body,
    required this.muted,
    required this.lime,
    required this.onLime,
    required this.onLimeSurface,
    required this.stroke,
    required this.danger,
    required this.onDanger,
    required this.dangerSurface,
    required this.scrim,
  });

  /// Fondo di ogni schermata. Le superfici ci galleggiano sopra: nel chiaro
  /// sono più bianche del fondo, nello scuro più chiare del fondo. In entrambi
  /// i casi una card si stacca per luminosità, non per contorno.
  final Color background;

  /// Card, righe, sheet, menu: tutto ciò che sta "sopra" il fondo.
  final Color surface;

  /// Riempimento neutro *dentro* una superficie: righe delle serie, campi
  /// degli sheet, chip. È lo stesso tono del fondo schermata — è ciò che fa
  /// sembrare questi elementi "scavati", e vale nei due temi perché in un
  /// incavo si vede il fondo, qualunque sia.
  final Color fill;

  /// La superficie piena che spicca: pillola dell'azione principale, tab bar
  /// flottante, barra del timer, snackbar.
  ///
  /// Nel chiaro è la cosa più scura dello schermo. Nello scuro non può essere
  /// la più chiara (vedi la nota di classe sul lime), quindi è un gradino
  /// sopra le card: abbastanza per leggersi come un blocco, non tanto da
  /// spegnere l'accento che ci sta dentro.
  final Color inkSurface;

  /// Testo e icone sopra [inkSurface].
  final Color onInkSurface;

  /// Inchiostro: titoli, testo primario, icone.
  final Color ink;

  /// Testo dei paragrafi lunghi (descrizione, note): un filo meno contrastato
  /// di [ink], perché a paragrafo il contrasto pieno stanca. Vale nei due
  /// temi, in direzioni opposte.
  final Color body;

  /// Dati secondari: label di sezione, meta, placeholder.
  final Color muted;

  /// Accento. Un solo elemento per schermata lo porta, ed è lo stesso lime nei
  /// due temi: è il colore del marchio, non una funzione della luminosità.
  final Color lime;

  /// Testo e icone sopra [lime]. Identico nei due temi, perché il lime lo è.
  final Color onLime;

  /// Una superficie chiara *appoggiata* sul lime: il pallino della spunta
  /// sulla scheda in uso. Identica nei due temi per la stessa ragione — sopra
  /// una card lime il contorno non cambia, quindi non deve cambiare nemmeno
  /// quello che ci sta dentro, o la stessa card sembrerebbe due card.
  final Color onLimeSurface;

  /// Contorni: si disegnano con `inset` (un box shadow interno o un [Border]
  /// da 1px), mai come divider a piena larghezza.
  final Color stroke;

  /// Azioni distruttive. Compare come *testo* (voce di menu, "Rimuovi serie")
  /// o come fondo dell'unica conferma finale di eliminazione. Come il lime,
  /// non si capovolge.
  final Color danger;

  /// Testo sopra un pieno [danger]. Identico nei due temi.
  final Color onDanger;

  /// Velo dietro un dato distruttivo (chip "Interrotta"): il rosa pieno come
  /// fondo di un testo non si legge, questo sì. Nel chiaro è un rosa
  /// lavatissimo, nello scuro un rosso quasi nero — in entrambi è il rosa
  /// portato al livello del fondo.
  final Color dangerSurface;

  /// Velo sotto sheet e dialog. Al buio è più coprente: sotto un velo al 40%
  /// una pagina già scura resterebbe leggibile, e lo sheet non si staccherebbe.
  final Color scrim;

  /// Il tema chiaro: i valori del file di design. I ruoli in più rispetto agli
  /// otto colori disegnati non aggiungono colori — ripetono `ink` e `surface`
  /// sotto il nome del loro ruolo, che è ciò che permette al tema scuro di
  /// separarli (vedi la nota di classe).
  static const AppPalette light = AppPalette(
    background: Color(0xFFF4F4F6),
    surface: Color(0xFFFFFFFF),
    fill: Color(0xFFF4F4F6),
    inkSurface: Color(0xFF192126),
    onInkSurface: Color(0xFFFFFFFF),
    ink: Color(0xFF192126),
    body: Color(0xFF232A3A),
    muted: Color(0xFF8C9092),
    lime: Color(0xFFBBF246),
    onLime: Color(0xFF192126),
    onLimeSurface: Color(0xFFFFFFFF),
    stroke: Color(0xFFD4D8E0),
    danger: Color(0xFFFF5678),
    onDanger: Color(0xFF192126),
    dangerSurface: Color(0xFFFFE3EA),
    scrim: Color(0x66192126),
  );

  /// Il tema scuro.
  ///
  /// Le distanze fra i ruoli sono quelle del chiaro, misurate: la card si
  /// stacca dal fondo di 1,13:1 come lì fa di 1,10:1, l'incavo rientra dello
  /// stesso passo, il blocco pieno sta un gradino sopra le card (1,60:1).
  /// Il testo invece sta **meglio** che nel chiaro, dove il design accetta un
  /// `muted` a 2,9:1: qui inchiostro, prosa, secondario e rosa passano tutti
  /// AA sul fondo e sulle card (7,4:1 il secondario, 6,1:1 il rosa). Al buio
  /// non è generosità, è il minimo perché RNF-04 (leggibilità a distanza, col
  /// telefono per terra) valga anche in palestra a luci basse.
  static const AppPalette dark = AppPalette(
    background: Color(0xFF0E1216),
    surface: Color(0xFF181F24),
    fill: Color(0xFF0E1216),
    inkSurface: Color(0xFF36414A),
    onInkSurface: Color(0xFFF2F4F6),
    ink: Color(0xFFF2F4F6),
    body: Color(0xFFD9DEE5),
    muted: Color(0xFF9CA3A8),
    lime: Color(0xFFBBF246),
    onLime: Color(0xFF192126),
    onLimeSurface: Color(0xFFFFFFFF),
    stroke: Color(0xFF2A3238),
    danger: Color(0xFFFF5678),
    onDanger: Color(0xFF192126),
    dangerSurface: Color(0xFF3A1C25),
    scrim: Color(0x99070A0C),
  );

  /// La palette di una luminosità. Sono due e sole due: un tema in più
  /// sarebbe una palette disegnata, non un ramo aggiunto qui.
  static AppPalette of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;
}
