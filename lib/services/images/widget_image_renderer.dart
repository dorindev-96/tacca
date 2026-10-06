import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Altezza logica che un widget prende alla larghezza dell'albero fuori
/// schermo con cui è stata creata (vedi [WidgetImageRenderer.measure]).
typedef WidgetHeightMeasure = double Function(Widget widget);

/// Disegna un widget **fuori dall'albero dell'app** e ne restituisce il PNG.
///
/// Serve a esportare un contenuto più alto dello schermo (una scheda intera,
/// RF-01) come immagine: dentro l'albero non si potrebbe, perché un
/// `RepaintBoundary` in una lista dipinge solo la parte visibile del viewport.
/// Qui invece si monta un albero usa-e-getta con una `RenderView` tutta sua,
/// larga quanto chiesto e **senza limite in altezza**: il widget si misura da
/// solo e la `RenderView` prende la sua taglia (`sizedByChild`).
///
/// Lo stesso albero sa anche solo **misurare** ([measure]): è ciò che serve a
/// un contenuto lungo per decidere dove andare a pagina nuova prima di essere
/// disegnato.
///
/// Il widget passato deve quindi essere autosufficiente — niente `Expanded`,
/// niente `ListView`, e il proprio [Directionality]/[Localizations]/[Theme]
/// addosso, perché sopra di lui non c'è nessun `MaterialApp`.
class WidgetImageRenderer {
  const WidgetImageRenderer({
    this.maxPixels = 24000000,
    this.maxDimension = 12000,
  });

  /// Numero massimo di pixel dell'immagine prodotta (~24 megapixel di
  /// default): la protezione contro l'allocazione da centinaia di MB su un
  /// telefono.
  final int maxPixels;

  /// Lato massimo in pixel. Non è una questione di memoria ma di chi deve
  /// **aprire** l'immagine: parecchi decoder (BitmapFactory di Android in
  /// testa, e con lui buona parte delle app di messaggistica) si fermano
  /// intorno ai 16384 px per lato, e un'immagine più lunga non viene
  /// mostrata affatto.
  final double maxDimension;

  /// Renderizza [widget] e ritorna i byte PNG.
  ///
  /// [pixelRatio] è la densità richiesta (3 = "retina"); viene ridotta se
  /// l'immagine sfonderebbe [maxPixels] o [maxDimension].
  Future<Uint8List> renderPng({
    required Widget widget,
    required double width,
    double pixelRatio = 3,
  }) async {
    final tree = _OffscreenTree(width: width);
    try {
      final size = tree.layout(widget);
      final image = await tree.paint(pixelRatio: _ratioFor(size, pixelRatio));
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) {
          throw StateError('Codifica PNG non riuscita.');
        }
        return data.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    } finally {
      tree.dispose();
    }
  }

  /// Presta a [body] un metro per sapere quanto sono alti dei widget alla
  /// larghezza [width], senza disegnarne nessuno.
  ///
  /// L'albero fuori schermo è uno solo per tutta la durata di [body]: le
  /// misure successive aggiornano il widget montato invece di ricostruire
  /// tutto, quindi un'impaginazione che prova decine di pagine candidate
  /// resta veloce. Il metro vale solo dentro [body]: dopo, l'albero è
  /// smontato.
  T measure<T>({
    required double width,
    required T Function(WidgetHeightMeasure measure) body,
  }) {
    final tree = _OffscreenTree(width: width);
    try {
      return body((widget) => tree.layout(widget).height);
    } finally {
      tree.dispose();
    }
  }

  /// La densità davvero usata: quella chiesta, abbassata quanto basta a
  /// stare dentro [maxPixels] e [maxDimension]. Si abbassa la definizione,
  /// non si rifiuta l'export: un contenuto lunghissimo resta condivisibile.
  double _ratioFor(Size size, double requested) {
    final longestSide = math.max(size.width, size.height);
    final pixels = size.width * size.height;
    if (longestSide <= 0 || pixels <= 0) return requested;
    return math.min(
      requested,
      math.min(maxDimension / longestSide, math.sqrt(maxPixels / pixels)),
    );
  }
}

/// L'albero usa-e-getta: una `RenderView` larga [width] e libera in altezza,
/// con sopra un `RepaintBoundary` da cui si ricava l'immagine.
///
/// [layout] si può chiamare più volte con widget diversi: la seconda volta
/// l'adapter aggiorna l'elemento già montato, come farebbe un normale
/// rebuild, e solo ciò che è cambiato si rimisura.
class _OffscreenTree {
  factory _OffscreenTree({required double width}) {
    final view = WidgetsBinding.instance.platformDispatcher.implicitView;
    if (view == null) {
      throw StateError('Nessuna vista disponibile per il rendering.');
    }

    // Larghezza fissa, altezza libera: il vincolo non è "tight", quindi
    // RenderView si dimensiona sul figlio invece di imporgli una taglia.
    final constraints = BoxConstraints(minWidth: width, maxWidth: width);
    final boundary = RenderRepaintBoundary();
    final renderView = RenderView(
      view: view,
      child: boundary,
      configuration: ViewConfiguration(
        logicalConstraints: constraints,
        physicalConstraints: constraints,
      ),
    );
    final pipelineOwner = PipelineOwner()..rootNode = renderView;
    renderView.prepareInitialFrame();

    final focusManager = FocusManager();
    return _OffscreenTree._(
      boundary: boundary,
      renderView: renderView,
      pipelineOwner: pipelineOwner,
      focusManager: focusManager,
      buildOwner: BuildOwner(focusManager: focusManager),
    );
  }

  _OffscreenTree._({
    required this.boundary,
    required this.renderView,
    required this.pipelineOwner,
    required this.focusManager,
    required this.buildOwner,
  });

  final RenderRepaintBoundary boundary;
  final RenderView renderView;
  final PipelineOwner pipelineOwner;
  final FocusManager focusManager;
  final BuildOwner buildOwner;

  RenderObjectToWidgetElement<RenderBox>? _element;

  /// Monta [widget] (o lo sostituisce a quello di prima) e ne ritorna la
  /// taglia.
  Size layout(Widget widget) {
    final element = RenderObjectToWidgetAdapter<RenderBox>(
      container: boundary,
      child: widget,
    ).attachToRenderTree(buildOwner, _element);
    _element = element;
    buildOwner
      ..buildScope(element)
      ..finalizeTree();
    pipelineOwner.flushLayout();
    return boundary.size;
  }

  /// Dipinge ciò che [layout] ha montato per ultimo.
  Future<ui.Image> paint({required double pixelRatio}) {
    pipelineOwner
      ..flushCompositingBits()
      ..flushPaint();
    return boundary.toImage(pixelRatio: pixelRatio);
  }

  /// Smonta l'albero nell'ordine che il framework si aspetta: prima i figli
  /// (svuotando l'adapter, così `finalizeTree` li disattiva e smonta come
  /// farebbe un normale rebuild), poi il distacco dei render object, infine
  /// la radice — che è anche ciò che deregistra la `GlobalObjectKey`
  /// dell'adapter. Saltare questo giro lascerebbe in giro un albero completo
  /// per ogni condivisione.
  void dispose() {
    final element = _element;
    if (element != null) {
      RenderObjectToWidgetAdapter<RenderBox>(
        container: boundary,
      ).attachToRenderTree(buildOwner, element);
      buildOwner
        ..buildScope(element)
        ..finalizeTree();
    }

    renderView.child = null;
    pipelineOwner.rootNode = null;

    if (element != null) {
      element.deactivate();
      element.unmount();
    }

    renderView.dispose();
    pipelineOwner.dispose();
    focusManager.dispose();
  }
}
