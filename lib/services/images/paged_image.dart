import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'widget_image_renderer.dart';

/// Un contenuto da esportare come **una o più immagini** della stessa
/// larghezza, che sa da sé dove andare a pagina nuova.
///
/// Esiste perché un'immagine sola, per un contenuto lungo, non arriva
/// leggibile a nessuno: le app di messaggistica la ridimensionano sul lato
/// lungo (WhatsApp intorno ai 1600 px in qualità standard, Telegram ai 1280),
/// e una striscia alta e stretta diventa larga poche centinaia di pixel,
/// qualunque fosse la sua definizione di partenza. Pagine con le proporzioni
/// di uno schermo di telefono, invece, arrivano come arriva uno screenshot.
///
/// `services/` non sa cosa ci sia dentro: l'impaginazione la decide chi
/// conosce il contenuto ([paginate]), il servizio presta solo il metro e
/// disegna le pagine che gli tornano indietro.
abstract interface class PagedImage {
  /// Larghezza logica di ogni pagina; i pixel veri li decide la densità del
  /// rendering.
  double get pageWidth;

  /// Divide il contenuto in pagine, ognuna un widget autosufficiente da
  /// disegnare a [pageWidth].
  ///
  /// [measure] dice quanto sarebbe alta una pagina candidata: è la misura vera
  /// del widget, non un calcolo che la imita, così l'impaginazione non può
  /// divergere da ciò che poi viene disegnato.
  List<Widget> paginate(WidgetHeightMeasure measure);
}

/// Una pagina: i pezzi da [start] incluso a [end] escluso.
typedef PageRange = ({int start, int end});

/// Divide in pagine una sequenza di [count] pezzi indivisibili, riempiendo
/// ogni pagina il più possibile senza superare [maxHeight].
///
/// [heightOf] è l'altezza della pagina fatta dei pezzi da `start` a `end`,
/// cornice compresa (testata, firma, margini). Si assume che aggiungere un
/// pezzo non accorci mai la pagina: è ciò che permette di cercare la fine di
/// ogni pagina a salti raddoppiati e poi per bisezione, invece che un pezzo
/// alla volta. I salti partono dall'inizio della pagina, così nessuna pagina
/// candidata è più lunga del doppio di quella vera: misurare è costruire e
/// impaginare dei widget, e una candidata con mezza scheda dentro costerebbe
/// quanto mezza scheda.
///
/// Un pezzo più alto di una pagina intera non si perde e non blocca niente:
/// va da solo su una pagina più alta delle altre.
///
/// [canBreakBefore] dice se una pagina può cominciare dal pezzo `index`:
/// un'intestazione in fondo a una pagina, con il suo contenuto sulla
/// successiva, non intesta niente, e un esercizio rimasto solo in cima a una
/// pagina sembra un altro blocco. Se lo spazio finisce dove non si può
/// andare a capo, la pagina si chiude prima, all'ultimo punto in cui si può;
/// se non ce n'è nessuno si va a capo comunque — l'altezza è un limite, il
/// bel taglio una preferenza.
///
/// Senza pezzi c'è comunque una pagina (vuota): la cornice da sola è già
/// qualcosa da mostrare.
List<PageRange> paginateRanges({
  required int count,
  required double maxHeight,
  required double Function(int start, int end) heightOf,
  bool Function(int index)? canBreakBefore,
}) {
  if (count <= 0) return const [(start: 0, end: 0)];

  final pages = <PageRange>[];
  var start = 0;
  while (start < count) {
    // La fine più lontana che sta nella pagina: almeno un pezzo, anche se da
    // solo sfonda l'altezza.
    var fits = start + 1;
    if (heightOf(start, fits) <= maxHeight) {
      var tooFar = count + 1;
      for (var step = 1; fits < count; step *= 2) {
        final probe = math.min(fits + step, count);
        if (heightOf(start, probe) > maxHeight) {
          tooFar = probe;
          break;
        }
        fits = probe;
      }
      while (tooFar - fits > 1) {
        final middle = (fits + tooFar) ~/ 2;
        if (heightOf(start, middle) <= maxHeight) {
          fits = middle;
        } else {
          tooFar = middle;
        }
      }
    }

    var end = fits;
    if (canBreakBefore != null && end < count) {
      var allowed = end;
      while (allowed > start + 1 && !canBreakBefore(allowed)) {
        allowed--;
      }
      if (canBreakBefore(allowed)) end = allowed;
    }

    pages.add((start: start, end: end));
    start = end;
  }
  return pages;
}
