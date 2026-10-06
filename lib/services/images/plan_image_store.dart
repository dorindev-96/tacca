import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

/// Salvataggio e compressione delle immagini delle schede (§6.4, RF-03).
///
/// Gli originali vivono a piena risoluzione in
/// `getApplicationDocumentsDirectory()/plan_images/`; le entity salvano solo
/// il path relativo. La versione compressa (lato lungo ~1600 px, JPEG q80)
/// esiste solo in memoria, per ridurre i token vision prima dell'upload.
class PlanImageStore {
  PlanImageStore({Future<Directory> Function()? documentsDirectory})
    : _documentsDirectory =
          documentsDirectory ?? getApplicationDocumentsDirectory;

  static const _directoryName = 'plan_images';

  /// La cartella dei documenti dell'app; nei test, una cartella temporanea.
  final Future<Directory> Function() _documentsDirectory;

  /// Salva l'originale su disco e ritorna il path relativo da mettere in
  /// `WorkoutPlan.imagePaths`.
  Future<String> saveOriginal(Uint8List bytes) async {
    final directory = await _imagesDirectory();
    final fileName =
        '${DateTime.now().microsecondsSinceEpoch}_${bytes.length}.jpg';
    await File('${directory.path}/$fileName').writeAsBytes(bytes, flush: true);
    return '$_directoryName/$fileName';
  }

  /// File assoluto di un path relativo salvato in `imagePaths`.
  Future<File> fileForRelativePath(String relativePath) async {
    final documents = await _documentsDirectory();
    return File('${documents.path}/$relativePath');
  }

  /// Porta fra le immagini delle schede un file già scritto altrove (quelle
  /// di un backup da ripristinare) e ritorna il path relativo da mettere in
  /// `WorkoutPlan.imagePaths`.
  ///
  /// Il nome lo decide questa classe, come in [saveOriginal]: quello che
  /// l'immagine aveva nel telefono da cui viene non conta, e da un file che
  /// arriva da fuori non si prende nessun path.
  Future<String> adopt(File file) async {
    final directory = await _imagesDirectory();
    final fileName =
        '${DateTime.now().microsecondsSinceEpoch}_${await file.length()}.jpg';
    final target = '${directory.path}/$fileName';
    try {
      await file.rename(target);
    } on FileSystemException {
      // Cartella temporanea e documenti possono stare su volumi diversi:
      // allora si copia, e l'originale lo pulisce chi l'ha scritto.
      await file.copy(target);
    }
    return '$_directoryName/$fileName';
  }

  /// Elimina un'immagine salvata. Non è un errore se non c'è già più.
  Future<void> delete(String relativePath) async {
    final file = await fileForRelativePath(relativePath);
    if (await file.exists()) await file.delete();
  }

  /// Elimina le immagini che nessuna scheda nomina più, tenendo [keep].
  ///
  /// Serve dopo un ripristino, che sostituisce tutte le schede: le immagini
  /// di quelle vecchie restano su disco senza più nessuno che le apra, e un
  /// ripristino dopo l'altro le accumulerebbe.
  Future<void> deleteAllExcept(Set<String> keep) async {
    final directory = await _imagesDirectory();
    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      final name = entity.path.split('/').last;
      if (!keep.contains('$_directoryName/$name')) await entity.delete();
    }
  }

  /// Comprime per l'upload AI: lato lungo max ~1600 px, JPEG qualità 80.
  Future<Uint8List> compressForUpload(Uint8List bytes) async {
    return FlutterImageCompress.compressWithList(
      bytes,
      minWidth: 1600,
      minHeight: 1600,
      quality: 80,
      format: CompressFormat.jpeg,
    );
  }

  Future<Directory> _imagesDirectory() async {
    final documents = await _documentsDirectory();
    final directory = Directory('${documents.path}/$_directoryName');
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }
}
