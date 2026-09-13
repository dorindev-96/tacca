import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tacca/services/images/widget_image_renderer.dart';

/// Disegno di un widget fuori dall'albero dell'app.
///
/// È il pezzo che rende possibile esportare una scheda **intera**: quello che
/// si verifica qui è che l'altezza la decida il contenuto (non lo schermo) e
/// che l'albero usa-e-getta si smonti, così condividere due volte non lascia
/// niente in giro.
void main() {
  /// Larghezza e altezza in pixel lette dall'header IHDR del PNG.
  (int, int) pngSize(Uint8List bytes) {
    expect(bytes.sublist(0, 8), [
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
    ], reason: 'i byte prodotti non sono un PNG');
    final header = ByteData.sublistView(bytes);
    return (header.getUint32(16), header.getUint32(20));
  }

  Widget box(double height) => Directionality(
    textDirection: TextDirection.ltr,
    child: SizedBox(
      height: height,
      child: const ColoredBox(color: Color(0xFFBBF246)),
    ),
  );

  testWidgets('il contenuto detta l\'altezza, il chiamante la larghezza', (
    tester,
  ) async {
    final bytes = await tester.runAsync(
      () => const WidgetImageRenderer().renderPng(
        widget: box(500),
        width: 200,
        pixelRatio: 2,
      ),
    );

    expect(pngSize(bytes!), (400, 1000));
  });

  testWidgets('un contenuto più alto dello schermo non viene tagliato', (
    tester,
  ) async {
    // Il default della finestra di test è 600 di altezza: qui se ne chiedono
    // dieci volte tanti, che è il caso della scheda lunga.
    final bytes = await tester.runAsync(
      () => const WidgetImageRenderer().renderPng(
        widget: box(6000),
        width: 100,
        pixelRatio: 1,
      ),
    );

    expect(pngSize(bytes!), (100, 6000));
  });

  testWidgets('oltre il tetto di pixel cala la densità, non si rinuncia', (
    tester,
  ) async {
    final bytes = await tester.runAsync(
      () => const WidgetImageRenderer(
        maxPixels: 10000,
      ).renderPng(widget: box(100), width: 100, pixelRatio: 4),
    );

    // 100×100 a densità 4 farebbe 160.000 pixel: la densità scende a 1.
    expect(pngSize(bytes!), (100, 100));
  });

  testWidgets(
    'anche il lato lungo ha un tetto: un PNG che nessuno apre non è un export',
    (tester) async {
      final bytes = await tester.runAsync(
        () => const WidgetImageRenderer(
          maxDimension: 900,
        ).renderPng(widget: box(600), width: 100, pixelRatio: 3),
      );

      // 600 di altezza a densità 3 farebbe 1800 px: la densità scende a 1,5.
      expect(pngSize(bytes!), (150, 900));
    },
  );

  testWidgets('due esportazioni di fila non lasciano niente in giro', (
    tester,
  ) async {
    const renderer = WidgetImageRenderer();
    await tester.runAsync(() async {
      await renderer.renderPng(widget: box(50), width: 50, pixelRatio: 1);
      await renderer.renderPng(widget: box(50), width: 50, pixelRatio: 1);
    });

    expect(tester.takeException(), isNull);
  });
}
