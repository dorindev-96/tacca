import 'dart:ui' show Rect;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../services/backup/backup_files.dart';
import '../../../services/backup/backup_format.dart';
import '../../../services/backup/backup_service.dart';

/// Che cosa sta facendo il backup in questo momento. Una cosa sola per
/// volta: due export di fila, o un ripristino durante un export, non hanno
/// senso, e la pagina spegne i pulsanti finché si lavora.
enum BackupActivity { idle, exporting, reading, restoring }

/// Perché un'operazione sul backup non è riuscita: alla pagina serve solo
/// per scegliere il messaggio.
enum BackupFailure {
  exportFailed,
  notABackup,
  newerVersion,
  damaged,
  readFailed,
  restoreFailed,
}

/// L'esito dell'ultima operazione, da mostrare una volta.
///
/// I costruttori non sono `const` apposta: due errori uguali di fila devono
/// essere due oggetti diversi. Un esito costante sarebbe sempre la stessa
/// istanza, `emit` scarterebbe il secondo come stato invariato e il secondo
/// tentativo fallito non direbbe niente.
sealed class BackupOutcome {
  BackupOutcome();
}

final class BackupRestored extends BackupOutcome {
  BackupRestored({required this.plans, required this.logs});

  final int plans;
  final int logs;
}

final class BackupFailed extends BackupOutcome {
  BackupFailed(this.reason);

  final BackupFailure reason;
}

class BackupState {
  const BackupState({this.activity = BackupActivity.idle, this.outcome});

  final BackupActivity activity;

  /// Ogni esito è un oggetto nuovo: la pagina lo mostra quando cambia, anche
  /// se è lo stesso errore di prima.
  final BackupOutcome? outcome;

  bool get isBusy => activity != BackupActivity.idle;
}

/// Backup locale (Impostazioni → Backup): esporta l'archivio in un file e lo
/// consegna al foglio di condivisione, oppure ne legge uno e, dopo la
/// conferma dell'utente, lo ripristina.
///
/// La conferma la chiede la pagina, fra [pickBackup] e [restore]: il cubit
/// legge e verifica il file *prima*, così all'utente si può dire che cosa
/// sta per sostituire che cosa, e un file sbagliato si scopre quando non è
/// ancora cambiato niente.
class BackupCubit extends Cubit<BackupState> {
  BackupCubit({required BackupService backup, required BackupFiles files})
    : _backup = backup,
      _files = files,
      super(const BackupState());

  final BackupService _backup;
  final BackupFiles _files;

  /// Quanto c'è adesso nell'app: è ciò che un ripristino sostituirebbe.
  ({int plans, int logs}) currentCounts() => _backup.currentCounts();

  /// Scrive il backup e apre il foglio di condivisione. [originRect] è
  /// l'ancora del popover su iPad.
  Future<void> export({Rect? originRect}) async {
    if (state.isBusy) return;
    _emit(const BackupState(activity: BackupActivity.exporting));
    try {
      final file = await _backup.export();
      // Se nel frattempo la pagina è stata chiusa, il foglio di condivisione
      // comparirebbe sopra un'altra schermata, per un export che l'utente ha
      // abbandonato. Il file resta nella cartella temporanea fino al
      // prossimo export.
      if (isClosed) return;
      await _files.share(file, originRect: originRect);
      _emit(const BackupState());
    } catch (_) {
      _emit(BackupState(outcome: BackupFailed(BackupFailure.exportFailed)));
    }
  }

  /// Fa scegliere un file all'utente, lo legge e lo verifica.
  ///
  /// Ritorna il backup pronto da ripristinare, oppure null se l'utente ha
  /// rinunciato o se il file non va — in quel caso lo dice l'esito. Un
  /// backup restituito va poi passato a [restore] o a [discard].
  Future<BackupPreview?> pickBackup() async {
    if (state.isBusy) return null;

    final String? path;
    try {
      path = await _files.pick();
    } catch (_) {
      _emit(BackupState(outcome: BackupFailed(BackupFailure.readFailed)));
      return null;
    }
    if (path == null) return null;

    _emit(const BackupState(activity: BackupActivity.reading));
    try {
      final preview = await _backup.inspect(path);
      if (isClosed) {
        await _backup.discard(preview);
        return null;
      }
      _emit(const BackupState());
      return preview;
    } on BackupFormatException catch (error) {
      _emit(
        BackupState(
          outcome: BackupFailed(switch (error.problem) {
            BackupProblem.notABackup => BackupFailure.notABackup,
            BackupProblem.newerVersion => BackupFailure.newerVersion,
            BackupProblem.damaged => BackupFailure.damaged,
          }),
        ),
      );
    } catch (_) {
      _emit(BackupState(outcome: BackupFailed(BackupFailure.readFailed)));
    } finally {
      // Letto o rifiutato, il file scelto non serve più: quello che serviva
      // è già stato estratto.
      await _files.release(path);
    }
    return null;
  }

  /// Sostituisce l'archivio con [preview], dopo che l'utente ha confermato.
  ///
  /// Schede, storico e sessione aperta si aggiornano da soli: i loro cubit
  /// osservano il database.
  Future<void> restore(BackupPreview preview) async {
    if (state.isBusy) return;
    _emit(const BackupState(activity: BackupActivity.restoring));
    try {
      await _backup.restore(preview);
      _emit(
        BackupState(
          outcome: BackupRestored(plans: preview.plans, logs: preview.logs),
        ),
      );
    } catch (_) {
      // La transazione del database è una sola: se non è andata, l'archivio
      // è quello di prima.
      _emit(BackupState(outcome: BackupFailed(BackupFailure.restoreFailed)));
    }
  }

  /// L'utente non ha confermato: si butta ciò che la lettura aveva preparato.
  Future<void> discard(BackupPreview preview) => _backup.discard(preview);

  /// La pagina può chiudersi mentre si lavora: l'operazione finisce lo
  /// stesso, ma non c'è più nessuno a cui dirlo.
  void _emit(BackupState state) {
    if (!isClosed) emit(state);
  }
}
