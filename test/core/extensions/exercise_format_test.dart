import 'package:flutter_test/flutter_test.dart';
import 'package:tacca/core/extensions/exercise_format.dart';
import 'package:tacca/data/entities/exercise.dart';
import 'package:tacca/l10n/app_localizations_en.dart';
import 'package:tacca/l10n/app_localizations_it.dart';

void main() {
  final it = AppLocalizationsIt();

  group('ExerciseFormat', () {
    test('volume: serie×ripetizioni, sole ripetizioni, o niente', () {
      expect(Exercise(name: 'x', sets: 3, reps: '8').volume, '3×8');
      expect(Exercise(name: 'x', sets: 3).volume, '3×?');
      expect(Exercise(name: 'x', reps: 'max').volume, 'max');
      expect(Exercise(name: 'x').volume, '');
    });

    test('la prescrizione intera, tradotta, nell\'ordine di lettura', () {
      final exercise = Exercise(
        name: 'Panca piana',
        sets: 4,
        reps: '6',
        load: '70% 1RM',
        restSeconds: 90,
        durationSeconds: 30,
      );
      expect(
        exercise.prescription(it),
        '4×6 · 70% 1RM · Recupero 90s · Durata 30s',
      );
      expect(
        exercise.prescription(AppLocalizationsEn()),
        '4×6 · 70% 1RM · Rest 90s · Duration 30s',
      );
    });

    test('le parti assenti non compaiono', () {
      expect(
        Exercise(name: 'x', durationSeconds: 300).prescription(it),
        'Durata 300s',
      );
      expect(Exercise(name: 'x', load: '').prescription(it), '');
    });
  });
}
