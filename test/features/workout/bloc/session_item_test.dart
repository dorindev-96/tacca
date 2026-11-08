import 'package:flutter_test/flutter_test.dart';
import 'package:tacca/data/entities/block.dart';
import 'package:tacca/data/entities/exercise.dart';
import 'package:tacca/data/entities/log_entry.dart';
import 'package:tacca/data/repositories/workout_log_repository.dart';
import 'package:tacca/features/workout/bloc/session_item.dart';

import '../../../support/fakes.dart';

void main() {
  SessionItem item({String? reps = '8-10'}) => SessionItem(
    index: 0,
    entry: LogEntry(exerciseNameSnapshot: 'Panca piana'),
    block: Block.ofType(BlockType.standard),
    exercise: Exercise(name: 'Panca piana', sets: 3, reps: reps),
  );

  LastPerformance lastTime(double? weightKg, String? reps) => LastPerformance(
    performedAt: DateTime(2026, 8, 8),
    sets: [buildLogSet(1, weightKg: weightKg, reps: reps)],
  );

  group('setPrefill', () {
    test('senza riferimenti: niente peso, ripetizioni della scheda', () {
      expect(setPrefill(item(), 1), (weightKg: null, reps: '8-10'));
    });

    test('la volta scorsa, quando la sessione non ha ancora serie', () {
      expect(setPrefill(item(), 1, lastTime: lastTime(75, '8')), (
        weightKg: 75.0,
        reps: '8',
      ));
    });

    test('la serie prima in questa sessione vince sulla volta scorsa', () {
      final current = item();
      current.entry.sets.add(buildLogSet(1, weightKg: 85, reps: '6'));
      expect(setPrefill(current, 2, lastTime: lastTime(75, '8')), (
        weightKg: 85.0,
        reps: '6',
      ));
    });

    test('conta solo una serie *prima* di quella da riempire', () {
      final current = item();
      current.entry.sets.add(buildLogSet(3, weightKg: 90, reps: '4'));
      expect(setPrefill(current, 2, lastTime: lastTime(75, '8')), (
        weightKg: 75.0,
        reps: '8',
      ));
    });

    test('un riferimento senza ripetizioni ripiega sulla scheda', () {
      final current = item();
      current.entry.sets.add(buildLogSet(1, weightKg: 85));
      expect(setPrefill(current, 2), (weightKg: 85.0, reps: '8-10'));
      expect(setPrefill(item(), 1, lastTime: lastTime(70, '  ')), (
        weightKg: 70.0,
        reps: '8-10',
      ));
    });
  });
}
