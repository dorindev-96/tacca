import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Disegna un widget **fuori dall'albero dell'app** e ne restituisce il PNG.
///
/// Serve a esportare un contenuto più alto dello schermo (una scheda intera,
/// RF-01) come immagine unica: dentro l'albero non si potrebbe, perché un
/// `RepaintBoundary` in una lista dipinge solo la parte visibile del viewport.
/// Qui invece si monta un albero usa-e-getta con una `RenderView` tutta sua,
/// larga [width] e **senza limite in altezza**: il widget si misura da solo e
/// la `RenderView` prende la sua taglia (`sizedByChild`).
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
  /// mostrata affatto. Una scheda lunga sfonda in altezza molto prima di
  /// sfondare in megapixel.
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
    final buildOwner = BuildOwner(focusManager: focusManager);
    final element = RenderObjectToWidgetAdapter<RenderBox>(
      container: boundary,
      child: widget,
    ).attachToRenderTree(buildOwner);

    try {
      buildOwner
        ..buildScope(element)
        ..finalizeTree();
      pipelineOwner
        ..flushLayout()
        ..flushCompositingBits()
        ..flushPaint();

      final image = await boundary.toImage(
        pixelRatio: _ratioFor(boundary.size, pixelRatio),
      );
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
      _tearDown(
        boundary: boundary,
        renderView: renderView,
        pipelineOwner: pipelineOwner,
        buildOwner: buildOwner,
        element: element,
        focusManager: focusManager,
      );
    }
  }

  /// La densità davvero usata: quella chiesta, abbassata quanto basta a
  /// stare dentro [maxPixels] e [maxDimension]. Si abbassa la definizione,
  /// non si rifiuta l'export: una scheda lunghissima resta condivisibile.
  double _ratioFor(Size size, double requested) {
    final longestSide = math.max(size.width, size.height);
    final pixels = size.width * size.height;
    if (longestSide <= 0 || pixels <= 0) return requested;
    return math.min(
      requested,
      math.min(maxDimension / longestSide, math.sqrt(maxPixels / pixels)),
    );
  }

  /// Smonta l'albero usa-e-getta nell'ordine che il framework si aspetta:
  /// prima i figli (svuotando l'adapter, così `finalizeTree` li disattiva e
  /// smonta come farebbe un normale rebuild), poi il distacco dei render
  /// object, infine la radice — che è anche ciò che deregistra la
  /// `GlobalObjectKey` dell'adapter. Saltare questo giro lascerebbe in giro un
  /// albero completo per ogni condivisione.
  void _tearDown({
    required RenderRepaintBoundary boundary,
    required RenderView renderView,
    required PipelineOwner pipelineOwner,
    required BuildOwner buildOwner,
    required RenderObjectToWidgetElement<RenderBox> element,
    required FocusManager focusManager,
  }) {
    RenderObjectToWidgetAdapter<RenderBox>(
      container: boundary,
    ).attachToRenderTree(buildOwner, element);
    buildOwner
      ..buildScope(element)
      ..finalizeTree();

    renderView.child = null;
    pipelineOwner.rootNode = null;

    element.deactivate();
    element.unmount();

    renderView.dispose();
    pipelineOwner.dispose();
    focusManager.dispose();
  }
}
