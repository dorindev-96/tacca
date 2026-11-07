import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_native_ocr/flutter_native_ocr.dart';
import 'package:path_provider/path_provider.dart';

/// OCR on-device (RF-03): quando il modello scelto non supporta le
/// immagini, l'import trasforma prima le foto in testo qui, così anche i
/// modelli solo-testo restano utilizzabili senza mai lasciare il device per
/// il riconoscimento.
abstract interface class OcrService {
  /// Testo riconosciuto nell'immagine, riga per riga; stringa vuota se non
  /// trova testo leggibile.
  Future<String> recognizeText(Uint8List bytes);
}

/// Implementazione su `flutter_native_ocr` (Vision su iOS, ML Kit su
/// Android). Il plugin lavora su un path di file, non su bytes in memoria:
/// l'immagine passa per un file temporaneo, ripulito subito dopo.
class NativeOcrService implements OcrService {
  NativeOcrService({FlutterNativeOcr? ocr}) : _ocr = ocr ?? FlutterNativeOcr();

  final FlutterNativeOcr _ocr;

  @override
  Future<String> recognizeText(Uint8List bytes) async {
    final directory = await getTemporaryDirectory();
    final file = File(
      '${directory.path}/ocr_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await file.writeAsBytes(bytes, flush: true);
    try {
      return await _ocr.recognizeText(file.path);
    } finally {
      if (file.existsSync()) await file.delete();
    }
  }
}

/// L'OCR di più foto, una alla volta.
extension OcrPages on OcrService {
  /// Il testo di ciascuna di [images], nello stesso ordine e senza spazi ai
  /// bordi. Una foto illeggibile — o un errore del riconoscimento — diventa
  /// una pagina vuota invece di far perdere le altre (RNF-05).
  Future<List<String>> recognizePages(List<Uint8List> images) async {
    final pages = <String>[];
    for (final bytes in images) {
      try {
        pages.add((await recognizeText(bytes)).trim());
      } catch (_) {
        pages.add('');
      }
    }
    return pages;
  }
}
