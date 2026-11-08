import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tacca/app/theme.dart';
import 'package:tacca/core/extensions/exercise_format.dart';
import 'package:tacca/data/entities/block.dart';
import 'package:tacca/data/entities/exercise.dart';
import 'package:tacca/data/entities/log_entry.dart';
import 'package:tacca/features/workout/bloc/session_item.dart';
import 'package:tacca/features/workout/widgets/session_exercise_card.dart';
import 'package:tacca/l10n/app_localizations.dart';

void main() {
  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets('la prescrizione tradotta regge sulla card lime a 360dp '
        '(${locale.languageCode})', (tester) async {
      tester.view.physicalSize = const Size(360 * 3, 1600 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final exercise = Exercise(
        name: 'Kurzhantel-Schrägbankdrücken',
        sets: 4,
        reps: '8-10',
        load: '70% 1RM',
        restSeconds: 120,
        durationSeconds: 45,
      );
      final item = SessionItem(
        index: 0,
        entry: LogEntry(exerciseNameSnapshot: exercise.name),
        block: Block.ofType(BlockType.standard),
        exercise: exercise,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.of(Brightness.light),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: locale,
          home: Scaffold(
            body: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                SessionExerciseCard(
                  item: item,
                  isCurrent: true,
                  lastPerformance: null,
                  onToggleSet: (_) {},
                  onEditSet: (_) {},
                  onFocus: () {},
                  onStartRest: () {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final l10n = await AppLocalizations.delegate.load(locale);
      // Il testo è quello dell'ARB, non "rec 120s"…
      expect(find.text(exercise.prescription(l10n)), findsOneWidget);
      // …e nessun overflow: un RenderFlex che sfora è un'eccezione nel test.
      expect(tester.takeException(), isNull);
    });
  }
}
