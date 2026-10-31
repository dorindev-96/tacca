import 'package:flutter/services.dart';

/// Gli appunti di sistema dietro un'interfaccia.
///
/// Servono all'import "copia e incolla" (RF-03): l'app ci scrive il prompt da
/// portare in una chat AI qualsiasi e ci rilegge la risposta. Come per
/// fotocamera, OCR e wake lock, il canale di piattaforma sta in `services/`:
/// i Cubit non lo toccano mai direttamente.
abstract interface class ClipboardService {
  Future<void> write(String text);

  /// Testo negli appunti; null se non contengono niente di testuale.
  Future<String?> read();
}

class SystemClipboardService implements ClipboardService {
  const SystemClipboardService();

  @override
  Future<void> write(String text) =>
      Clipboard.setData(ClipboardData(text: text));

  @override
  Future<String?> read() async =>
      (await Clipboard.getData(Clipboard.kTextPlain))?.text;
}
