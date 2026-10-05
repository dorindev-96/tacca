import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tacca/data/db/object_box.dart';
import 'package:tacca/data/entities/block.dart';
import 'package:tacca/data/entities/exercise.dart';
import 'package:tacca/data/entities/log_set.dart';
import 'package:tacca/data/entities/workout_day.dart';
import 'package:tacca/data/entities/workout_log.dart';
import 'package:tacca/data/entities/workout_plan.dart';
import 'package:tacca/data/repositories/backup_repository.dart';
import 'package:tacca/data/repositories/plan_repository.dart';
import 'package:tacca/data/repositories/workout_log_repository.dart';
import 'package:tacca/objectbox.g.dart';
import 'package:tacca/services/backup/backup_format.dart';
import 'package:tacca/services/backup/backup_service.dart';
import 'package:tacca/services/images/plan_image_store.dart';

import '../../data/objectbox_test_support.dart';

/// Il backup dall'inizio alla fine, con database e file veri: quello che
/// esce da un telefono deve rientrare identico in un altro, e quello che non
/// è un backup intero non deve toccare niente.
void main() {
  final skip = objectBoxNativeLibSkipReason();

  late Directory root;
  final opened = <ObjectBox>[];

  setUp(() => root = Directory.systemTemp.createTempSync('backup-test-'));

  tearDown(() {
    for (final store in opened) {
      store.close();
    }
    opened.clear();
    root.deleteSync(recursive: true);
  });

  /// Un telefono: database, immagini e cartella temporanea suoi.
  ({
    ObjectBox objectBox,
    PlanRepository plans,
    WorkoutLogRepository logs,
    PlanImageStore images,
    BackupService backup,
    Directory documents,
    Directory temporary,
  })
  phone(String name) {
    final database = Directory('${root.path}/$name/db')
      ..createSync(recursive: true);
    final documents = Directory('${root.path}/$name/documents')
      ..createSync(recursive: true);
    final temporary = Directory('${root.path}/$name/tmp')
      ..createSync(recursive: true);
    final objectBox = ObjectBox.fromStore(
      Store(getObjectBoxModel(), directory: database.path),
    );
    opened.add(objectBox);
    final images = PlanImageStore(documentsDirectory: () async => documents);
    return (
      objectBox: objectBox,
      plans: ObjectBoxPlanRepository(objectBox),
      logs: ObjectBoxWorkoutLogRepository(objectBox),
      images: images,
      backup: BackupService(
        repository: ObjectBoxBackupRepository(objectBox),
        imageStore: images,
        temporaryDirectory: () async => temporary,
        clock: () => DateTime(2026, 10, 5, 18, 30),
      ),
      documents: documents,
      temporary: temporary,
    );
  }

  final photo = Uint8List.fromList(List.generate(5000, (i) => i % 251));

  /// Due schede (una in uso con la foto dell'import, una archiviata) e due
  /// allenamenti, uno dei quali della scheda poi eliminata.
  Future<void> seed(
    ({
      ObjectBox objectBox,
      PlanRepository plans,
      WorkoutLogRepository logs,
      PlanImageStore images,
      BackupService backup,
      Directory documents,
      Directory temporary,
    })
    device,
  ) async {
    final now = DateTime(2026, 9, 1, 9);
    final photoPath = await device.images.saveOriginal(photo);

    final ppl = WorkoutPlan(
      name: 'Push Pull Legs',
      notes: 'Dalla foto della palestra',
      createdAt: now,
      updatedAt: now,
      imagePaths: [photoPath],
    );
    final day = WorkoutDay(label: 'Giorno A', sortOrder: 0);
    final block = Block.ofType(BlockType.superset, sortOrder: 0)..rounds = 3;
    block.exercises
      ..add(Exercise(name: 'Panca piana', sets: 4, reps: '8', sortOrder: 0))
      ..add(Exercise(name: 'Rematore', sets: 4, reps: '10', sortOrder: 1));
    day.blocks.add(block);
    ppl.days.add(day);
    final pplId = device.plans.savePlan(ppl);
    device.plans.setActivePlan(pplId);

    final old = WorkoutPlan(
      name: 'Vecchia scheda',
      createdAt: now,
      updatedAt: now,
    );
    old.days.add(WorkoutDay(label: 'Unico'));
    final oldId = device.plans.savePlan(old);
    device.plans.setArchived(oldId, archived: true);

    final saved = device.plans.getById(pplId)!;
    final log = device.logs.startSession(
      plan: saved,
      day: saved.days.first,
      startedAt: DateTime(2026, 9, 2, 18),
    );
    log.entries.first.sets.add(
      LogSet(
        setNumber: 1,
        reps: '8',
        weightKg: 70,
        completedAt: DateTime(2026, 9, 2, 18, 5),
      ),
    );
    log
      ..status = WorkoutStatus.completed
      ..finishedAt = DateTime(2026, 9, 2, 19);
    device.logs.saveLog(log);

    final gone = WorkoutPlan(name: 'Eliminata', createdAt: now, updatedAt: now);
    gone.days.add(WorkoutDay(label: 'Giorno 1'));
    final goneId = device.plans.savePlan(gone);
    final goneSaved = device.plans.getById(goneId)!;
    final orphan = device.logs.startSession(
      plan: goneSaved,
      day: goneSaved.days.first,
      startedAt: DateTime(2026, 8, 1, 18),
    )..status = WorkoutStatus.aborted;
    device.logs.saveLog(orphan);
    device.plans.deletePlan(goneId);
  }

  List<WorkoutPlan> allPlans(ObjectBox objectBox) =>
      ObjectBoxBackupRepository(objectBox).readAll().plans;

  List<WorkoutLog> allLogs(ObjectBox objectBox) =>
      ObjectBoxBackupRepository(objectBox).readAll().logs;

  List<String> imageFiles(Directory documents) {
    final directory = Directory('${documents.path}/plan_images');
    if (!directory.existsSync()) return const [];
    return [for (final file in directory.listSync()) file.path];
  }

  test(
    'esportato da un telefono, si ripristina identico su un altro',
    () async {
      final from = phone('vecchio');
      await seed(from);
      final file = await from.backup.export();

      expect(file.path, endsWith('tacca-backup-2026-10-05-1830.tacca'));

      final to = phone('nuovo');
      final preview = await to.backup.inspect(file.path);
      expect((preview.plans, preview.logs), (2, 2));
      expect(preview.createdAt, DateTime(2026, 10, 5, 18, 30));

      await to.backup.restore(preview);

      final plans = {
        for (final plan in allPlans(to.objectBox)) plan.name: plan,
      };
      expect(plans.keys, unorderedEquals(['Push Pull Legs', 'Vecchia scheda']));

      final ppl = plans['Push Pull Legs']!;
      expect(ppl.isActive, isTrue);
      expect(ppl.notes, 'Dalla foto della palestra');
      final block = ppl.days.single.blocks.single;
      expect(block.type, BlockType.superset);
      expect(block.rounds, 3);
      expect(block.exercises.map((e) => e.name), ['Panca piana', 'Rematore']);
      expect(plans['Vecchia scheda']!.isArchived, isTrue);

      // La foto dell'import arriva con la scheda, sotto un nome nuovo.
      final restoredPhoto = await to.images.fileForRelativePath(
        ppl.imagePaths.single,
      );
      expect(await restoredPhoto.readAsBytes(), photo);

      final logs = allLogs(to.objectBox);
      final completed = logs.singleWhere(
        (log) => log.status == WorkoutStatus.completed,
      );
      // L'allenamento si ricollega alla scheda e al giorno ripristinati, con il
      // loro id nuovo.
      expect(completed.plan.target?.id, ppl.id);
      expect(completed.day.target?.id, ppl.days.single.id);
      final set = completed.entries.first.sets.single;
      expect((set.weightKg, set.reps), (70.0, '8'));

      // Quello della scheda eliminata resta, leggibile dagli snapshot.
      final orphan = logs.singleWhere(
        (log) => log.status == WorkoutStatus.aborted,
      );
      expect(orphan.plan.target, isNull);
      expect(orphan.planNameSnapshot, 'Eliminata');
    },
    skip: skip,
  );

  test('il ripristino sostituisce: due volte lo stesso backup non '
      'raddoppia niente', () async {
    final from = phone('vecchio');
    await seed(from);
    final file = await from.backup.export();

    final to = phone('nuovo');
    final old = WorkoutPlan(
      name: 'Già sul telefono nuovo',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      imagePaths: [
        await to.images.saveOriginal(Uint8List.fromList([1, 2])),
      ],
    );
    to.plans.savePlan(old);

    await to.backup.restore(await to.backup.inspect(file.path));
    await to.backup.restore(await to.backup.inspect(file.path));

    expect(allPlans(to.objectBox).map((p) => p.name), [
      'Push Pull Legs',
      'Vecchia scheda',
    ]);
    expect(allLogs(to.objectBox), hasLength(2));
    // Né la foto della scheda sostituita né le copie del primo ripristino:
    // resta solo l'immagine che una scheda nomina.
    expect(imageFiles(to.documents), hasLength(1));
  }, skip: skip);

  test('un file che non è un backup non tocca niente', () async {
    final to = phone('nuovo');
    await seed(to);
    final notABackup = File('${root.path}/foto.jpg')
      ..writeAsBytesSync(List.generate(20000, (i) => (i * 7) % 256));

    await expectLater(
      to.backup.inspect(notABackup.path),
      throwsA(
        isA<BackupFormatException>().having(
          (e) => e.problem,
          'problem',
          BackupProblem.notABackup,
        ),
      ),
    );
    expect(allPlans(to.objectBox), hasLength(2));
  }, skip: skip);

  test('un backup troncato non si ripristina', () async {
    final from = phone('vecchio');
    await seed(from);
    final file = await from.backup.export();
    final bytes = file.readAsBytesSync();
    // A metà della foto: un download interrotto.
    final truncated = File('${root.path}/troncato.tacca')
      ..writeAsBytesSync(bytes.sublist(0, bytes.length * 2 ~/ 3));

    final to = phone('nuovo');
    await expectLater(
      to.backup.inspect(truncated.path),
      throwsA(
        isA<BackupFormatException>().having(
          (e) => e.problem,
          'problem',
          BackupProblem.damaged,
        ),
      ),
    );
    expect(allPlans(to.objectBox), isEmpty);
    // E non lascia in giro le immagini estratte fin lì.
    expect(
      Directory('${to.temporary.path}/backup/restore').existsSync(),
      isFalse,
    );
  }, skip: skip);

  test('un backup decompresso a mano si ripristina lo stesso', () async {
    final from = phone('vecchio');
    await seed(from);
    final file = await from.backup.export();
    final plain = File('${root.path}/a-mano.tacca')
      ..writeAsBytesSync(gzip.decode(file.readAsBytesSync()));

    final to = phone('nuovo');
    await to.backup.restore(await to.backup.inspect(plain.path));

    expect(allPlans(to.objectBox), hasLength(2));
  }, skip: skip);

  test('rinunciare al ripristino non lascia file in giro', () async {
    final from = phone('vecchio');
    await seed(from);
    final file = await from.backup.export();

    final to = phone('nuovo');
    final preview = await to.backup.inspect(file.path);
    expect(
      Directory('${to.temporary.path}/backup/restore').existsSync(),
      isTrue,
    );

    await to.backup.discard(preview);

    expect(
      Directory('${to.temporary.path}/backup/restore').existsSync(),
      isFalse,
    );
    expect(allPlans(to.objectBox), isEmpty);
  }, skip: skip);

  test('una foto sparita dal disco non blocca il backup', () async {
    final from = phone('vecchio');
    await seed(from);
    for (final path in imageFiles(from.documents)) {
      File(path).deleteSync();
    }

    final file = await from.backup.export();
    final to = phone('nuovo');
    await to.backup.restore(await to.backup.inspect(file.path));

    final ppl = allPlans(
      to.objectBox,
    ).singleWhere((plan) => plan.name == 'Push Pull Legs');
    expect(ppl.imagePaths, isEmpty);
  }, skip: skip);

  test('due export che si accavallano non si pestano i piedi', () async {
    final from = phone('vecchio');
    await seed(from);

    // Stesso minuto, stesso nome di file: senza la coda del servizio il
    // secondo svuoterebbe la cartella e riaprirebbe il file mentre il primo
    // lo sta ancora scrivendo.
    final files = await Future.wait([
      from.backup.export(),
      from.backup.export(),
    ]);

    final to = phone('nuovo');
    final preview = await to.backup.inspect(files.last.path);
    expect((preview.plans, preview.logs), (2, 2));
  }, skip: skip);

  test('ogni export ripulisce quello di prima', () async {
    final from = phone('vecchio');
    await seed(from);
    final first = await from.backup.export();
    final second = await from.backup.export();

    expect(second.existsSync(), isTrue);
    expect(
      Directory('${from.temporary.path}/backup/export').listSync(),
      hasLength(1),
    );
    expect(first.path, second.path);
  }, skip: skip);
}
