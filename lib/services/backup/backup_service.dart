import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../data/repositories/backup_repository.dart';
import '../images/plan_image_store.dart';
import 'backup_format.dart';

/// Un backup letto e verificato da [BackupService.inspect], in attesa che
/// l'utente confermi il ripristino: quello che c'è dentro, e le immagini già
/// estratte su disco.
///
/// Leggere tutto **prima** di chiedere la conferma è ciò che rende il
/// ripristino sicuro: un file rotto o di un'altra app si scopre qui, quando
/// non è ancora cambiato niente, e non a metà della sostituzione.
class BackupPreview {
  const BackupPreview({required this.backup, required this.staging});

  /// Il contenuto del backup, verificato. Lo usa [BackupService.restore]:
  /// chi chiede conferma all'utente legge solo il riassunto qui sotto.
  final DecodedBackup backup;

  /// La cartella temporanea con le immagini già estratte, una per
  /// riferimento.
  final Directory staging;

  /// Quando è stato fatto il backup.
  DateTime get createdAt => backup.header.createdAt;

  int get plans => backup.header.plans;
  int get logs => backup.header.logs;
}

/// Backup locale dell'archivio: tutte le schede (con le foto originali degli
/// import) e tutti gli allenamenti in un file solo, che l'utente porta dove
/// vuole e da cui l'app può ripartire, anche su un altro telefono.
///
/// **Non contiene impostazioni né API key.** Le key vivono solo nel secure
/// storage e non escono mai in un export (vedi `SettingsRepository`); lingua,
/// tema e modello si rimettono in un attimo, e un backup che li riportasse
/// indietro sovrascriverebbe scelte fatte sul telefono nuovo.
///
/// Il ripristino **sostituisce** l'archivio, non lo unisce: è l'unico modo
/// in cui ripristinare due volte lo stesso backup non raddoppia ogni scheda.
/// Per questo la UI lo fa confermare dicendo quanto c'è adesso e quanto
/// arriva ([currentCounts], [BackupPreview]).
class BackupService {
  BackupService({
    required BackupRepository repository,
    required PlanImageStore imageStore,
    Future<Directory> Function()? temporaryDirectory,
    DateTime Function()? clock,
  }) : _repository = repository,
       _imageStore = imageStore,
       _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory,
       _clock = clock ?? DateTime.now;

  final BackupRepository _repository;
  final PlanImageStore _imageStore;
  final Future<Directory> Function() _temporaryDirectory;
  final DateTime Function() _clock;

  /// Quante righe di testo si leggono al massimo per trovare l'intestazione:
  /// la vera è di poche decine di caratteri. Senza un tetto, un file qualsiasi
  /// senza a capo (una foto scelta per sbaglio) verrebbe letto tutto in
  /// memoria come se fosse una riga sola.
  static const int _maxHeaderLength = 4096;

  /// La coda delle operazioni: export, lettura e ripristino passano uno alla
  /// volta in tutta l'app, non solo dentro una pagina.
  ///
  /// Il cubit spegne i pulsanti mentre lavora, ma il cubit è della pagina e
  /// questo servizio è dell'app: chi esce durante un export e rientra a
  /// farne un altro avrebbe due export che svuotano e riempiono la stessa
  /// cartella, e nello stesso minuto lo stesso file. Uno dei due ne
  /// condividerebbe uno scritto a metà.
  Future<void> _queue = Future<void>.value();

  Future<T> _oneAtATime<T>(Future<T> Function() operation) {
    final result = _queue.then((_) => operation());
    _queue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  /// Quante schede e quanti allenamenti ci sono adesso nell'app.
  ({int plans, int logs}) currentCounts() => _repository.count();

  /// Scrive l'intero archivio in un file nella cartella temporanea dell'app
  /// e lo restituisce, pronto da consegnare al foglio di condivisione.
  ///
  /// Il file di un export precedente si cancella qui: dopo la condivisione
  /// non si può, perché alcune app (la posta) leggono il file solo quando
  /// l'utente invia.
  Future<File> export() => _oneAtATime(_export);

  Future<File> _export() async {
    final data = _repository.readAll();
    final directory = await _freshDirectory('export');
    final file = File(
      '${directory.path}/${BackupFormat.fileNameFor(_clock())}',
    );

    // Le immagini da allegare, una volta sola anche quando più schede le
    // nominano (una scheda duplicata punta agli stessi file). Quella che non
    // c'è più su disco resta fuori: la scheda viaggia comunque.
    final imageRefs = <String, int>{};
    final imageFiles = <File>[];
    for (final plan in data.plans) {
      for (final path in plan.imagePaths) {
        if (imageRefs.containsKey(path)) continue;
        final image = await _imageStore.fileForRelativePath(path);
        if (!await image.exists()) continue;
        imageFiles.add(image);
        imageRefs[path] = imageFiles.length;
      }
    }
    final planIds = {for (final plan in data.plans) plan.id};
    final dayIds = {
      for (final plan in data.plans)
        for (final day in plan.days) day.id,
    };

    final out = file.openWrite();
    final lines = utf8.encoder.startChunkedConversion(
      gzip.encoder.startChunkedConversion(out),
    );
    try {
      void write(String line) => lines.add('$line\n');

      write(
        BackupEncoder.header(
          BackupHeader(
            createdAt: _clock(),
            plans: data.plans.length,
            logs: data.logs.length,
            images: imageFiles.length,
          ),
        ),
      );
      for (final plan in data.plans) {
        write(
          BackupEncoder.plan(
            plan,
            images: [
              for (final path in plan.imagePaths)
                if (imageRefs[path] case final ref?) ref,
            ],
          ),
        );
      }
      for (final log in data.logs) {
        // `target` e non `targetId`: un riferimento a una scheda eliminata
        // conserva l'id, ma non trova più niente.
        final planId = log.plan.target?.id;
        final dayId = log.day.target?.id;
        write(
          BackupEncoder.log(
            log,
            planRef: planIds.contains(planId) ? planId : null,
            dayRef: dayIds.contains(dayId) ? dayId : null,
          ),
        );
      }
      // Un'immagine alla volta, aspettando che arrivi su disco prima della
      // successiva: senza queste attese il file intero si accumulerebbe in
      // memoria prima di essere scritto.
      await out.flush();
      for (var i = 0; i < imageFiles.length; i++) {
        write(BackupEncoder.image(i + 1, await imageFiles[i].readAsBytes()));
        await out.flush();
      }
    } finally {
      lines.close();
      await out.done;
    }
    return file;
  }

  /// Legge il backup in [path] e lo verifica da cima a fondo, estraendone le
  /// immagini in una cartella temporanea. Non tocca niente dell'archivio:
  /// per quello c'è [restore], dopo la conferma; per rinunciare, [discard].
  ///
  /// Lancia [BackupFormatException] se il file non è un backup, viene da una
  /// versione più recente dell'app o è rotto.
  Future<BackupPreview> inspect(String path) =>
      _oneAtATime(() => _inspect(path));

  Future<BackupPreview> _inspect(String path) async {
    final file = File(path);
    final header = BackupDecoder.readHeader(await _firstLine(file));
    final decoder = BackupDecoder(header);
    final staging = await _freshDirectory('restore');

    try {
      var isHeader = true;
      await for (final line in _lines(file)) {
        if (isHeader) {
          isHeader = false;
          continue;
        }
        if (line.trim().isEmpty) continue;
        final image = decoder.add(line);
        if (image != null) {
          await File(
            '${staging.path}/${image.ref}',
          ).writeAsBytes(image.bytes, flush: true);
        }
      }
      return BackupPreview(backup: decoder.finish(), staging: staging);
    } on FormatException catch (error) {
      await _deleteQuietly(staging);
      // gzip e UTF-8 si rompono così: il file era un backup (l'intestazione
      // c'era), ma più avanti è rovinato.
      throw BackupFormatException(BackupProblem.damaged, error.message);
    } catch (_) {
      await _deleteQuietly(staging);
      rethrow;
    }
  }

  /// Sostituisce l'archivio con il backup di [preview].
  ///
  /// Prima le immagini, poi il database in un'unica transazione: se qualcosa
  /// va storto prima della transazione si cancellano le immagini appena
  /// portate dentro e l'archivio resta com'era; dopo, le immagini delle
  /// schede sostituite non le usa più nessuno e si cancellano.
  Future<void> restore(BackupPreview preview) =>
      _oneAtATime(() => _restore(preview));

  Future<void> _restore(BackupPreview preview) async {
    final backup = preview.backup;
    final adopted = <int, String>{};
    try {
      for (final refs in backup.planImages.values) {
        for (final ref in refs) {
          if (adopted.containsKey(ref)) continue;
          adopted[ref] = await _imageStore.adopt(
            File('${preview.staging.path}/$ref'),
          );
        }
      }
      for (final plan in backup.data.plans) {
        plan.imagePaths = [
          for (final ref in backup.planImages[plan] ?? const <int>[])
            adopted[ref]!,
        ];
      }
      _repository.replaceAll(backup.data);
    } catch (_) {
      for (final path in adopted.values) {
        await _quietly(() => _imageStore.delete(path));
      }
      rethrow;
    } finally {
      await _deleteQuietly(preview.staging);
    }

    await _quietly(() => _imageStore.deleteAllExcept(adopted.values.toSet()));
  }

  /// Butta ciò che [inspect] ha preparato, quando l'utente non conferma.
  Future<void> discard(BackupPreview preview) =>
      _oneAtATime(() => _deleteQuietly(preview.staging));

  /// La prima riga del file, cioè l'intestazione, letta senza mai tenere in
  /// memoria più di [_maxHeaderLength] caratteri.
  Future<String> _firstLine(File file) async {
    final buffer = StringBuffer();
    try {
      await for (final chunk in _text(file)) {
        final newline = chunk.indexOf('\n');
        if (newline >= 0) {
          buffer.write(chunk.substring(0, newline));
          break;
        }
        buffer.write(chunk);
        if (buffer.length > _maxHeaderLength) break;
      }
    } on FormatException {
      // Né gzip né UTF-8: un file binario qualsiasi.
      throw const BackupFormatException(
        BackupProblem.notABackup,
        'Il file non è testo.',
      );
    }
    if (buffer.length > _maxHeaderLength) {
      throw const BackupFormatException(
        BackupProblem.notABackup,
        'Nessuna intestazione nelle prime righe.',
      );
    }
    return buffer.toString();
  }

  Stream<String> _lines(File file) =>
      _text(file).transform(const LineSplitter());

  /// Il testo del file, decompresso se è compresso: i backup dell'app lo
  /// sono sempre, ma uno decompresso a mano per guardarci dentro deve potersi
  /// ancora ripristinare.
  Stream<String> _text(File file) async* {
    final bytes = await _isGzip(file)
        ? file.openRead().transform(gzip.decoder)
        : file.openRead();
    yield* bytes.transform(utf8.decoder);
  }

  static Future<bool> _isGzip(File file) async {
    final handle = await file.open();
    try {
      final magic = await handle.read(2);
      return magic.length == 2 && magic[0] == 0x1f && magic[1] == 0x8b;
    } finally {
      await handle.close();
    }
  }

  /// Una cartella di lavoro vuota sotto la cartella temporanea dell'app: ciò
  /// che vi è rimasto da un giro precedente (un export già condiviso, un
  /// ripristino interrotto) si cancella qui.
  Future<Directory> _freshDirectory(String name) async {
    final temporary = await _temporaryDirectory();
    final directory = Directory('${temporary.path}/backup/$name');
    await _deleteQuietly(directory);
    return directory.create(recursive: true);
  }

  static Future<void> _deleteQuietly(Directory directory) => _quietly(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  /// Le pulizie sono un di più: se non riescono, l'operazione principale è
  /// comunque andata come doveva.
  static Future<void> _quietly(Future<void> Function() cleanup) async {
    try {
      await cleanup();
    } on FileSystemException {
      // best effort
    }
  }
}
