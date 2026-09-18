import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tacca/app/theme.dart';
import 'package:tacca/core/design/app_palette.dart';
import 'package:tacca/core/design/linear_icons.dart';
import 'package:tacca/core/widgets/app_sheet.dart';
import 'package:tacca/core/widgets/linear_icon.dart';
import 'package:tacca/core/widgets/meta_chip.dart';
import 'package:tacca/core/widgets/pill_button.dart';
import 'package:tacca/data/entities/block.dart';
import 'package:tacca/data/entities/exercise.dart';
import 'package:tacca/data/entities/log_entry.dart';
import 'package:tacca/data/entities/workout_plan.dart';
import 'package:tacca/features/plans/widgets/plan_list_tile.dart';
import 'package:tacca/features/workout/bloc/session_item.dart';
import 'package:tacca/features/workout/widgets/session_exercise_card.dart';
import 'package:tacca/l10n/app_localizations.dart';

/// Le superfici lime, disegnate nei **due** temi.
///
/// Il lime non si capovolge: è lo stesso colore al chiaro e al buio. Quindi
/// ogni testo e ogni icona che ci sta sopra deve restare scura in entrambi, e
/// il modo di sbagliare è sempre lo stesso — usare `ink`, che al buio diventa
/// quasi bianco, invece di `onLime`. A occhio non si vede finché non si accende
/// il tema scuro, e questi test sono il posto in cui si vede prima.
void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    required Brightness brightness,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('it'),
        theme: AppTheme.of(brightness),
        home: Scaffold(body: child),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Il colore con cui un testo viene davvero disegnato.
  Color colorOf(WidgetTester tester, String text) {
    final widget = tester.widget<Text>(find.text(text));
    return widget.style!.color!;
  }

  Color iconColorOf(WidgetTester tester, LinearIconData icon) {
    final widget = tester.widget<LinearIcon>(
      find.byWidgetPredicate((w) => w is LinearIcon && w.icon == icon),
    );
    return widget.color!;
  }

  WorkoutPlan plan() {
    final now = DateTime(2026, 1, 1);
    return WorkoutPlan(
      name: 'Scheda in uso',
      createdAt: now,
      updatedAt: now,
      isActive: true,
    )..id = 1;
  }

  Widget tile() => PlanListTile(
    plan: plan(),
    highlighted: true,
    onOpen: () {},
    onEdit: () {},
    onDuplicate: () {},
    onArchiveToggle: () {},
    onDelete: () {},
  );

  /// L'esercizio corrente della sessione: l'altra card lime dell'app, quella
  /// che si guarda col telefono per terra a metà serie.
  Widget sessionCard() {
    final block = Block.ofType(BlockType.standard);
    final exercise = Exercise(
      name: 'Back Squat',
      sets: 3,
      reps: '8-10',
      restSeconds: 120,
    );
    block.exercises.add(exercise);
    return SessionExerciseCard(
      item: SessionItem(
        index: 0,
        entry: LogEntry(exerciseNameSnapshot: 'Back Squat'),
        block: block,
        exercise: exercise,
      ),
      isCurrent: true,
      lastPerformance: null,
      onToggleSet: (_) {},
      onEditSet: (_) {},
      onFocus: () {},
    );
  }

  for (final brightness in Brightness.values) {
    final label = brightness == Brightness.dark ? 'scuro' : 'chiaro';

    testWidgets('tema $label: la card della scheda in uso resta leggibile', (
      tester,
    ) async {
      await pump(tester, tile(), brightness: brightness);

      // Il nome e il disco della spunta non seguono il tema: sono appoggiati
      // sul lime, che è lo stesso nei due.
      expect(colorOf(tester, 'Scheda in uso'), AppPalette.light.onLime);
      expect(iconColorOf(tester, AppIcons.check), AppPalette.light.onLime);
    });

    testWidgets('tema $label: la chip in evidenza resta leggibile', (
      tester,
    ) async {
      await pump(
        tester,
        const MetaChip(label: 'In uso', tone: ChipTone.accent),
        brightness: brightness,
      );

      expect(colorOf(tester, 'In uso'), AppPalette.light.onLime);
    });

    testWidgets('tema $label: la pillola lime resta leggibile', (tester) async {
      await pump(
        tester,
        PillButton(label: 'Ferma', tone: PillTone.accent, onPressed: () {}),
        brightness: brightness,
      );

      expect(colorOf(tester, 'Ferma'), AppPalette.light.onLime);
    });

    testWidgets('tema $label: la card dell\'esercizio corrente resta '
        'leggibile', (tester) async {
      await pump(tester, sessionCard(), brightness: brightness);

      // Nome, prescrizione, conteggio e valore della serie: tutto quello che
      // nel tema segue `ink` e sopra il lime non può.
      expect(colorOf(tester, 'Back Squat'), AppPalette.light.onLime);
      expect(colorOf(tester, '3×8-10 · rec 120s'), AppPalette.light.onLime);
      expect(colorOf(tester, '0/3 serie'), AppPalette.light.onLime);
      // Tre serie, tre trattini: nessuno dei tre può restare inchiostro.
      final dashes = tester
          .widgetList<Text>(find.text('—'))
          .map((text) => text.style!.color)
          .toSet();
      expect(dashes, {AppPalette.light.onLime});
    });

    testWidgets('tema $label: l\'opzione consigliata di uno sheet resta '
        'leggibile', (tester) async {
      await pump(
        tester,
        SheetOption(
          icon: AppIcons.wave,
          title: 'Incolla da una chat',
          subtitle: 'Senza API key',
          highlighted: true,
          onTap: () {},
        ),
        brightness: brightness,
      );

      expect(colorOf(tester, 'Incolla da una chat'), AppPalette.light.onLime);
      expect(iconColorOf(tester, AppIcons.wave), AppPalette.light.onLime);
      // Anche la spiegazione: è lo stesso inchiostro, solo più trasparente.
      expect(
        colorOf(tester, 'Senza API key'),
        AppPalette.light.onLime.withValues(alpha: 0.72),
      );
    });
  }

  testWidgets('la stessa riga *non* evidenziata segue invece il tema', (
    tester,
  ) async {
    // Il controprova: se seguisse il tema anche sul lime, il test qui sopra
    // passerebbe per il motivo sbagliato (cioè perché non cambia mai nulla).
    await pump(
      tester,
      SheetOption(icon: AppIcons.wave, title: 'Foto', onTap: () {}),
      brightness: Brightness.dark,
    );
    expect(colorOf(tester, 'Foto'), AppPalette.dark.ink);

    await pump(
      tester,
      SheetOption(icon: AppIcons.wave, title: 'Foto', onTap: () {}),
      brightness: Brightness.light,
    );
    expect(colorOf(tester, 'Foto'), AppPalette.light.ink);
  });
}
