import 'package:flutter_test/flutter_test.dart';
import 'package:tacca/features/settings/cubit/backup_cubit.dart';
import 'package:tacca/services/backup/backup_format.dart';

import '../../../support/fakes.dart';

/// Il backup visto dalla pagina: una cosa per volta, ogni esito detto una
/// volta, e niente che cambi finché l'utente non ha confermato.
void main() {
  late FakeBackupService service;
  late FakeBackupFiles files;
  late BackupCubit cubit;

  setUp(() {
    service = FakeBackupService(counts: (plans: 2, logs: 5));
    files = FakeBackupFiles(picked: '/tmp/tacca-backup.tacca');
    cubit = BackupCubit(backup: service, files: files);
  });

  tearDown(() => cubit.close());

  group('export', () {
    test('scrive il file e lo consegna al foglio di condivisione', () async {
      final states = <BackupActivity>[];
      final sub = cubit.stream.listen((s) => states.add(s.activity));

      await cubit.export();
      await pumpEventQueue();
      await sub.cancel();

      expect(files.shared.single.path, endsWith('.tacca'));
      expect(states, [BackupActivity.exporting, BackupActivity.idle]);
      expect(cubit.state.outcome, isNull);
    });

    test('se non riesce lo dice, e i pulsanti tornano attivi', () async {
      service.exportFails = true;

      await cubit.export();

      expect(files.shared, isEmpty);
      expect(cubit.state.isBusy, isFalse);
      expect(
        (cubit.state.outcome as BackupFailed?)?.reason,
        BackupFailure.exportFailed,
      );
    });
  });

  group('ripristino', () {
    test('legge il file e lo restituisce per la conferma, senza toccare '
        'niente', () async {
      final preview = await cubit.pickBackup();

      expect(preview, same(service.preview));
      expect(service.inspected, ['/tmp/tacca-backup.tacca']);
      expect(service.restored, isEmpty);
      expect(cubit.state.isBusy, isFalse);
    });

    test('chiudere il selettore non è un errore', () async {
      files.picked = null;

      expect(await cubit.pickBackup(), isNull);
      expect(service.inspected, isEmpty);
      expect(cubit.state.outcome, isNull);
    });

    test('un file che non va si scopre prima della conferma, col suo '
        'motivo', () async {
      for (final (problem, failure) in [
        (BackupProblem.notABackup, BackupFailure.notABackup),
        (BackupProblem.newerVersion, BackupFailure.newerVersion),
        (BackupProblem.damaged, BackupFailure.damaged),
      ]) {
        service.inspectProblem = problem;

        expect(await cubit.pickBackup(), isNull);
        expect((cubit.state.outcome as BackupFailed?)?.reason, failure);
      }
      expect(service.restored, isEmpty);
    });

    test('confermato, sostituisce e dice quanto è arrivato', () async {
      final preview = (await cubit.pickBackup())!;

      await cubit.restore(preview);

      expect(service.restored, [preview]);
      final outcome = cubit.state.outcome as BackupRestored?;
      expect((outcome?.plans, outcome?.logs), (3, 42));
    });

    test('se il ripristino non riesce lo dice', () async {
      service.restoreFails = true;
      final preview = (await cubit.pickBackup())!;

      await cubit.restore(preview);

      expect(cubit.state.isBusy, isFalse);
      expect(
        (cubit.state.outcome as BackupFailed?)?.reason,
        BackupFailure.restoreFailed,
      );
    });

    test('rinunciare butta ciò che la lettura aveva preparato', () async {
      final preview = (await cubit.pickBackup())!;

      await cubit.discard(preview);

      expect(service.discarded, [preview]);
      expect(service.restored, isEmpty);
    });
  });

  test('mentre lavora non parte una seconda operazione', () async {
    final first = cubit.export();
    final second = cubit.pickBackup();
    await first;

    expect(await second, isNull);
    expect(service.exportCount, 1);
    expect(service.inspected, isEmpty);
  });

  test('i conteggi di adesso vengono dal servizio', () {
    expect(cubit.currentCounts(), (plans: 2, logs: 5));
  });
}
