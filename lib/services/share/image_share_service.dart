import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

import '../images/widget_image_renderer.dart';

/// Esporta un widget come immagine e la consegna al foglio di condivisione di
/// sistema (WhatsApp, Telegram, mail, "Salva nelle foto"…).
///
/// È un'interfaccia per la stessa ragione di `LinkOpener`: nei widget test il
/// plugin di piattaforma non c'è, e soprattutto il disegno vero di
/// un'immagine da qualche megapixel non ha niente da fare dentro il test di
/// una pagina. Il widget da disegnare lo passa chi chiama, così `services/`
/// non conosce nessuna feature.
abstract interface class ImageShareService {
  /// Disegna [widget] alla larghezza logica [width] e apre il foglio di
  /// condivisione con il PNG risultante.
  ///
  /// [fileName] è il nome che vedrà chi riceve (estensione inclusa).
  /// [originRect] è l'ancora del popover su iPad, in coordinate globali:
  /// senza, il foglio compare in un angolo qualsiasi dello schermo.
  Future<void> shareWidgetAsImage({
    required Widget widget,
    required double width,
    required String fileName,
    String? text,
    Rect? originRect,
  });
}

class SystemImageShareService implements ImageShareService {
  const SystemImageShareService({this.renderer = const WidgetImageRenderer()});

  final WidgetImageRenderer renderer;

  @override
  Future<void> shareWidgetAsImage({
    required Widget widget,
    required double width,
    required String fileName,
    String? text,
    Rect? originRect,
  }) async {
    final bytes = await renderer.renderPng(widget: widget, width: width);
    await SharePlus.instance.share(
      ShareParams(
        // `XFile.fromData` non tocca il disco qui: è share_plus a scriverlo
        // nella cartella temporanea, che il sistema ripulisce da sé. Una
        // scheda condivisa non lascia file nostri in giro.
        files: [XFile.fromData(bytes, mimeType: 'image/png', name: fileName)],
        // `name` di un XFile creato da byte viene ignorato su mobile: il nome
        // vero passa da qui (vedi share_plus, issue #1548).
        fileNameOverrides: [fileName],
        text: text,
        subject: text,
        sharePositionOrigin: originRect,
      ),
    );
  }
}
