import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

import '../images/paged_image.dart';
import '../images/widget_image_renderer.dart';

/// Esporta un contenuto come una o più immagini e le consegna al foglio di
/// condivisione di sistema (WhatsApp, Telegram, mail, "Salva nelle foto"…).
///
/// È un'interfaccia per la stessa ragione di `LinkOpener`: nei widget test il
/// plugin di piattaforma non c'è, e soprattutto il disegno vero di qualche
/// immagine da qualche megapixel non ha niente da fare dentro il test di una
/// pagina. Il contenuto da disegnare lo passa chi chiama, già capace di
/// impaginarsi ([PagedImage]), così `services/` non conosce nessuna feature.
abstract interface class ImageShareService {
  /// Impagina [image], ne disegna ogni pagina come PNG e apre il foglio di
  /// condivisione con tutte le pagine, in ordine.
  ///
  /// [fileName] è il nome che vedrà chi riceve, **senza estensione**: una
  /// pagina sola diventa `nome.png`, più pagine `nome-1.png`, `nome-2.png`…
  /// (vedi [pageFileNames]). [originRect] è l'ancora del popover su iPad, in
  /// coordinate globali: senza, il foglio compare in un angolo qualsiasi
  /// dello schermo.
  Future<void> sharePagedImage({
    required PagedImage image,
    required String fileName,
    String? text,
    Rect? originRect,
  });
}

/// I nomi dei file delle [count] pagine di un'immagine chiamata [baseName]:
/// numerati solo se servono, e nell'ordine in cui vanno lette — è anche
/// l'ordine in cui la galleria di chi riceve le mette in fila.
List<String> pageFileNames(String baseName, int count) => count <= 1
    ? ['$baseName.png']
    : [for (var page = 1; page <= count; page++) '$baseName-$page.png'];

class SystemImageShareService implements ImageShareService {
  const SystemImageShareService({this.renderer = const WidgetImageRenderer()});

  final WidgetImageRenderer renderer;

  @override
  Future<void> sharePagedImage({
    required PagedImage image,
    required String fileName,
    String? text,
    Rect? originRect,
  }) async {
    final pages = renderer.measure(
      width: image.pageWidth,
      body: image.paginate,
    );
    final names = pageFileNames(fileName, pages.length);

    final files = <XFile>[];
    for (var i = 0; i < pages.length; i++) {
      final bytes = await renderer.renderPng(
        widget: pages[i],
        width: image.pageWidth,
      );
      // `XFile.fromData` non tocca il disco qui: è share_plus a scriverlo
      // nella cartella temporanea, che il sistema ripulisce da sé. Una
      // scheda condivisa non lascia file nostri in giro.
      files.add(XFile.fromData(bytes, mimeType: 'image/png', name: names[i]));
    }

    await SharePlus.instance.share(
      ShareParams(
        files: files,
        // `name` di un XFile creato da byte viene ignorato su mobile: il nome
        // vero passa da qui (vedi share_plus, issue #1548).
        fileNameOverrides: names,
        text: text,
        subject: text,
        sharePositionOrigin: originRect,
      ),
    );
  }
}
