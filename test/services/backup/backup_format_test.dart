import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tacca/data/entities/block.dart';
import 'package:tacca/data/entities/exercise.dart';
import 'package:tacca/data/entities/log_entry.dart';
import 'package:tacca/data/entities/log_set.dart';
import 'package:tacca/data/entities/workout_day.dart';
import 'package:tacca/data/entities/workout_log.dart';
import 'package:tacca/data/entities/workout_plan.dart';
import 'package:tacca/services/backup/backup_format.dart';

/// Il formato del file di backup, senza disco né database: quello che si
/// scrive deve tornare indietro identico, e quello che non è un backup intero
/// deve essere rifiutato prima di toccare qualunque cosa.
void main() {
  final createdAt = DateTime.utc(2026, 10, 5, 18, 30);

  BackupHeader header({int plans = 0, int logs = 0, int images = 0}) =>
      BackupHeader(
        createdAt: createdAt,
        plans: plans,
        logs: logs,
        images: images,
      );

  String headerLine({int plans = 0, int logs = 0, int images = 0}) =>
      BackupEncoder.header(header(plans: plans, logs: logs, images: images));

  /// Una scheda come esce dal database: con gli id, perché il backup li usa
  /// come riferimenti interni.
  WorkoutPlan seedPlan({int id = 7, bool active = false, DateTime? updated}) {
    final plan = WorkoutPlan(
      name: 'Push Pull Legs',
      description: 'Massa, 12 settimane',
      notes: 'Riscaldamento sempre',
      createdAt: DateTime(2026, 1, 1, 9),
      updatedAt: updated ?? DateTime(2026, 2, 1, 9),
      isActive: active,
    )..id = id;
    final day = WorkoutDay(label: 'Giorno A', notes: 'Petto', sortOrder: 0)
      ..id = id * 10;
    final standard = Block.ofType(BlockType.standard, sortOrder: 0);
    standard.exercises
      ..add(
        Exercise(
          name: 'Panca piana',
          sets: 4,
          reps: '8-10',
          load: '70% 1RM',
          restSeconds: 120,
          notes: 'Fermo al petto',
          sortOrder: 0,
        ),
      )
      ..add(Exercise(name: 'Croci', sets: 3, reps: '12', sortOrder: 1));
    final emom = Block.ofType(BlockType.emom, sortOrder: 1, notes: 'Leggero')
      ..intervalSeconds = 60
      ..totalMinutes = 10;
    emom.exercises.add(Exercise(name: 'Burpee', reps: '10', sortOrder: 0));
    final free = Block.ofType(BlockType.freeText, sortOrder: 2)
      ..freeTextContent = 'Stretching\n10 minuti';
    day.blocks
      ..add(standard)
      ..add(emom)
      ..add(free);
    plan.days.add(day);
    return plan;
  }

  WorkoutLog seedLog({
    WorkoutStatus status = WorkoutStatus.completed,
    DateTime? startedAt,
  }) {
    final start = startedAt ?? DateTime(2026, 3, 1, 18);
    final log = WorkoutLog(
      startedAt: start,
      finishedAt: status == WorkoutStatus.inProgress
          ? null
          : start.add(const Duration(hours: 1)),
      dbStatus: status.name,
      notes: 'Bene',
      planNameSnapshot: 'Push Pull Legs',
      dayLabelSnapshot: 'Giorno A',
    );
    final entry = LogEntry(exerciseNameSnapshot: 'Panca piana', sortOrder: 0);
    entry.sets
      ..add(
        LogSet(
          setNumber: 1,
          reps: '10',
          weightKg: 60,
          completedAt: start.add(const Duration(minutes: 5)),
        ),
      )
      ..add(
        LogSet(
          setNumber: 2,
          reps: '8',
          weightKg: 62.5,
          notes: 'Dura',
          completedAt: start.add(const Duration(minutes: 9)),
        ),
      );
    log.entries.add(entry);
    return log;
  }

  BackupFormatException formatError(void Function() body) {
    try {
      body();
    } on BackupFormatException catch (error) {
      return error;
    }
    fail('Nessuna BackupFormatException');
  }

  group('intestazione', () {
    test('si rilegge com\'è stata scritta', () {
      final read = BackupDecoder.readHeader(
        headerLine(plans: 2, logs: 5, images: 1),
      );

      expect(read.createdAt.isAtSameMomentAs(createdAt), isTrue);
      expect(read.createdAt.isUtc, isFalse, reason: 'le date tornano locali');
      expect((read.plans, read.logs, read.images), (2, 5, 1));
    });

    test('un file che non è un backup lo dice', () {
      expect(
        formatError(() => BackupDecoder.readHeader('ciao')).problem,
        BackupProblem.notABackup,
      );
      expect(
        formatError(
          () => BackupDecoder.readHeader('{"name":"Push Pull Legs"}'),
        ).problem,
        BackupProblem.notABackup,
      );
    });

    test('un backup di una versione più recente non si legge a metà', () {
      final line = jsonEncode({
        ...jsonDecode(headerLine()) as Map<String, Object?>,
        'version': BackupFormat.version + 1,
      });

      expect(
        formatError(() => BackupDecoder.readHeader(line)).problem,
        BackupProblem.newerVersion,
      );
    });

    test('il marchio senza il resto è un backup rotto, non un altro file', () {
      expect(
        formatError(
          () => BackupDecoder.readHeader('{"format":"tacca-backup"}'),
        ).problem,
        BackupProblem.damaged,
      );
    });
  });

  test('una scheda torna indietro intera, con tutto il suo albero', () {
    final decoder = BackupDecoder(header(plans: 1));
    decoder.add(BackupEncoder.plan(seedPlan(), images: const []));
    final plan = decoder.finish().data.plans.single;

    expect(plan.id, 0, reason: 'al ripristino prende un id nuovo');
    expect(plan.name, 'Push Pull Legs');
    expect(plan.description, 'Massa, 12 settimane');
    expect(plan.notes, 'Riscaldamento sempre');
    expect(plan.createdAt, DateTime(2026, 1, 1, 9));
    expect(plan.updatedAt, DateTime(2026, 2, 1, 9));

    final day = plan.days.single;
    expect((day.label, day.notes, day.sortOrder), ('Giorno A', 'Petto', 0));

    final [standard, emom, free] = day.blocks.toList();
    expect(standard.type, BlockType.standard);
    expect(standard.exercises.map((e) => e.name), ['Panca piana', 'Croci']);
    final panca = standard.exercises.first;
    expect(panca.sets, 4);
    expect(panca.reps, '8-10');
    expect(panca.load, '70% 1RM');
    expect(panca.restSeconds, 120);
    expect(panca.notes, 'Fermo al petto');

    expect(emom.type, BlockType.emom);
    expect((emom.intervalSeconds, emom.totalMinutes), (60, 10));
    expect(emom.notes, 'Leggero');
    expect(free.type, BlockType.freeText);
    expect(free.freeTextContent, 'Stretching\n10 minuti');
  });

  test('un allenamento torna indietro con serie, pesi e collegamenti', () {
    final source = seedPlan();
    final decoder = BackupDecoder(header(plans: 1, logs: 1))
      ..add(BackupEncoder.plan(source, images: const []))
      ..add(
        BackupEncoder.log(
          seedLog(),
          planRef: source.id,
          dayRef: source.days.first.id,
        ),
      );
    final data = decoder.finish().data;
    final log = data.logs.single;

    expect(log.status, WorkoutStatus.completed);
    expect(log.notes, 'Bene');
    expect(log.finishedAt, DateTime(2026, 3, 1, 19));
    // I riferimenti puntano agli oggetti del backup stesso: al ripristino si
    // ricollegano da sé, qualunque id prendano.
    expect(log.plan.target, same(data.plans.single));
    expect(log.day.target, same(data.plans.single.days.first));

    final sets = log.entries.single.sets.toList();
    expect(sets.map((s) => s.weightKg), [60.0, 62.5]);
    expect(sets.map((s) => s.reps), ['10', '8']);
    expect(sets.last.notes, 'Dura');
    expect(sets.first.completedAt, DateTime(2026, 3, 1, 18, 5));
  });

  test('un allenamento la cui scheda non c\'è più resta, senza scheda', () {
    final decoder = BackupDecoder(header(logs: 1))
      ..add(BackupEncoder.log(seedLog(), planRef: 99, dayRef: 990));
    final log = decoder.finish().data.logs.single;

    expect(log.plan.target, isNull);
    expect(log.day.target, isNull);
    // Lo storico si legge comunque: è fatto di snapshot.
    expect(log.planNameSnapshot, 'Push Pull Legs');
  });

  test('le immagini escono subito dal decoder e restano solo come '
      'riferimenti delle schede', () {
    final decoder = BackupDecoder(header(plans: 1, images: 2))
      ..add(BackupEncoder.plan(seedPlan(), images: const [2, 1]));
    final first = decoder.add(BackupEncoder.image(1, [1, 2, 3]));
    final second = decoder.add(BackupEncoder.image(2, [4, 5]));
    final backup = decoder.finish();

    expect(first?.ref, 1);
    expect(first?.bytes, [1, 2, 3]);
    expect(second?.bytes, [4, 5]);
    expect(backup.planImages[backup.data.plans.single], [2, 1]);
  });

  group('un backup incompleto o incoerente non si ripristina', () {
    test('mancano dei record rispetto all\'intestazione', () {
      // È il caso del file troncato esattamente fra due righe: ogni riga è
      // valida, solo i conti dicono che ne mancano.
      final decoder = BackupDecoder(header(plans: 2))
        ..add(BackupEncoder.plan(seedPlan(id: 1), images: const []));

      expect(formatError(decoder.finish).problem, BackupProblem.damaged);
    });

    test('una riga tagliata a metà', () {
      final line = BackupEncoder.plan(seedPlan(), images: const []);
      final decoder = BackupDecoder(header(plans: 1));

      expect(
        formatError(() => decoder.add(line.substring(0, 40))).problem,
        BackupProblem.damaged,
      );
    });

    test('una scheda che nomina un\'immagine che nel file non c\'è', () {
      final decoder = BackupDecoder(header(plans: 1))
        ..add(BackupEncoder.plan(seedPlan(), images: const [3]));

      expect(formatError(decoder.finish).problem, BackupProblem.damaged);
    });

    test('un campo obbligatorio che manca o ha il tipo sbagliato', () {
      final plan =
          jsonDecode(BackupEncoder.plan(seedPlan(), images: const []))
              as Map<String, Object?>;

      for (final broken in [
        {...plan}..remove('name'),
        {...plan, 'name': 42},
        {...plan, 'createdAt': 'ieri'},
        {...plan, 'isActive': 'sì'},
        {
          ...plan,
          'days': [
            {
              'ref': 1,
              'label': 'A',
              'blocks': [
                {'type': 'yoga'},
              ],
            },
          ],
        },
      ]) {
        final decoder = BackupDecoder(header(plans: 1));
        expect(
          formatError(() => decoder.add(jsonEncode(broken))).problem,
          BackupProblem.damaged,
          reason: '$broken',
        );
      }
    });

    test('un tipo di record sconosciuto', () {
      final decoder = BackupDecoder(header());
      expect(
        formatError(() => decoder.add('{"type":"settings"}')).problem,
        BackupProblem.damaged,
      );
    });

    test('la stessa scheda due volte', () {
      final line = BackupEncoder.plan(seedPlan(), images: const []);
      final decoder = BackupDecoder(header(plans: 2))..add(line);

      expect(
        formatError(() => decoder.add(line)).problem,
        BackupProblem.damaged,
      );
    });
  });

  group('le regole del database valgono anche per un file scritto a mano', () {
    test('una sola scheda in uso: la modificata più di recente', () {
      final decoder = BackupDecoder(header(plans: 3))
        ..add(
          BackupEncoder.plan(
            seedPlan(id: 1, active: true, updated: DateTime(2026, 1, 5)),
            images: const [],
          ),
        )
        ..add(
          BackupEncoder.plan(
            seedPlan(id: 2, active: true, updated: DateTime(2026, 4, 5)),
            images: const [],
          ),
        )
        ..add(
          BackupEncoder.plan(
            seedPlan(id: 3, active: true, updated: DateTime(2026, 9, 5))
              ..isArchived = true,
            images: const [],
          ),
        );
      final plans = decoder.finish().data.plans;

      // La terza è più recente ma archiviata: in uso non può esserlo.
      expect(plans.map((p) => p.isActive), [false, true, false]);
    });

    test('un solo allenamento aperto: il più recente', () {
      final decoder = BackupDecoder(header(logs: 2))
        ..add(
          BackupEncoder.log(
            seedLog(
              status: WorkoutStatus.inProgress,
              startedAt: DateTime(2026, 3, 1, 18),
            ),
          ),
        )
        ..add(
          BackupEncoder.log(
            seedLog(
              status: WorkoutStatus.inProgress,
              startedAt: DateTime(2026, 3, 8, 18),
            ),
          ),
        );
      final [older, newer] = decoder.finish().data.logs;

      expect(newer.status, WorkoutStatus.inProgress);
      expect(older.status, WorkoutStatus.aborted);
      // Chiuso all'ora della sua ultima serie, non a durata zero.
      expect(older.finishedAt, DateTime(2026, 3, 1, 18, 9));
    });
  });

  test('il nome del file dice quando è stato fatto il backup', () {
    expect(
      BackupFormat.fileNameFor(DateTime(2026, 10, 5, 8, 7)),
      'tacca-backup-2026-10-05-0807.tacca',
    );
  });
}
