import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

import 'backup_format.dart';

/// Dove va il file di un backup e da dove torna: il foglio di condivisione di
/// sistema per esportarlo, il selettore di file per sceglierne uno da
/// ripristinare.
///
/// L'export passa dal foglio di condivisione, come le immagini delle schede,
/// perché è lì che l'utente trova già tutte le sue destinazioni: "Salva in
/// File" su iOS, Drive, la posta, Quick Share o un altro telefono. L'app non
/// sceglie dove tenere i backup e non ne tiene nessuno.
///
/// È un'interfaccia per la stessa ragione di `ImageShareService`: nei widget
/// test i plugin di piattaforma non ci sono.
abstract interface class BackupFiles {
  /// Apre il foglio di condivisione con [file]. [originRect] è l'ancora del
  /// popover su iPad, in coordinate globali.
  Future<void> share(File file, {Rect? originRect});

  /// Fa scegliere un file all'utente e ne ritorna il path, o null se
  /// rinuncia. Il path è di una copia locale leggibile: i file in cloud li
  /// scarica il sistema prima di restituirli.
  Future<String?> pick();
}

class SystemBackupFiles implements BackupFiles {
  const SystemBackupFiles();

  @override
  Future<void> share(File file, {Rect? originRect}) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: BackupFormat.mimeType)],
        sharePositionOrigin: originRect,
      ),
    );
  }

  @override
  Future<String?> pick() async {
    // Nessun filtro per tipo: l'estensione `.tacca` non la conosce nessun
    // sistema, e un filtro per tipo MIME nasconderebbe proprio il backup.
    // Che il file sia un backup lo dice il suo contenuto, non il nome.
    final file = await openFile();
    return file?.path;
  }
}
