import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tacca/data/entities/block.dart';
import 'package:tacca/data/entities/exercise.dart';
import 'package:tacca/data/entities/workout_day.dart';
import 'package:tacca/data/entities/workout_plan.dart';
import 'package:tacca/features/plans/widgets/plan_share_image.dart';
import 'package:tacca/services/images/widget_image_renderer.dart';

/// L'immagine da mandare in chat: c'è dentro **tutta** la scheda, e sa
/// disegnarsi anche fuori dall'albero dell'app.
void main() {
  WorkoutPlan seedPlan({int days = 2}) {
    final now = DateTime(2026, 1, 1);
    final plan = WorkoutPlan(
      name: 'Scheda 2 Giorni',
      notes: 'Da integrare con camminate nei giorni di stop',
      createdAt: now,
      updatedAt: now,
    )..id = 1;

    for (var i = 0; i < days; i++) {
      final day = WorkoutDay(label: 'Giorno ${i + 1}', sortOrder: i)
        ..id = i + 1;
      final block = Block.ofType(BlockType.standard, sortOrder: 0);
      block.exercises.add(
        Exercise(
          name: 'Back Squat al Multipower ${i + 1}',
          sets: 3,
          reps: '8-10',
          restSeconds: 120,
          sortOrder: 0,
        ),
      );
      day.blocks.add(block);
      plan.days.add(day);
    }
    return plan;
  }

  Future<void> pumpPoster(WidgetTester tester, WorkoutPlan plan) async {
    // Il manifesto è alto quanto serve: la finestra di test di default lo
    // taglierebbe e farebbe scattare l'overflow.
    tester.view.physicalSize = const Size(PlanShareImage.logicalWidth, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      PlanShareImage(plan: plan, locale: const Locale('it')),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('porta con sé tutti i giorni, non solo il primo', (tester) async {
    await pumpPoster(tester, seedPlan());

    expect(find.text('Scheda 2 Giorni'), findsOneWidget);
    expect(find.text('2 giorni'), findsOneWidget);
    expect(find.text('Giorno 1'), findsOneWidget);
    expect(find.text('Giorno 2'), findsOneWidget);
    expect(find.text('Back Squat al Multipower 1'), findsOneWidget);
    expect(find.text('Back Squat al Multipower 2'), findsOneWidget);
    // Le note della scheda viaggiano con lei.
    expect(
      find.text('Da integrare con camminate nei giorni di stop'),
      findsOneWidget,
    );
    // Il tipo di blocco arriva dagli ARB — uno per giorno: se le
    // localizzazioni non si fossero caricate, qui non ci sarebbe niente.
    expect(find.text('Standard'), findsNWidgets(2));
  });

  testWidgets('lo stato della scheda resta nell\'app, non nell\'immagine', (
    tester,
  ) async {
    final plan = seedPlan()..isActive = true;
    await pumpPoster(tester, plan);

    // "In uso" è l'unico lime del dettaglio e dice "questa, adesso": a chi
    // riceve l'immagine non direbbe niente.
    expect(find.text('In uso'), findsNothing);
  });

  testWidgets('si disegna anche senza un MaterialApp sopra', (tester) async {
    final plan = seedPlan(days: 4);
    final Uint8List? bytes = await tester.runAsync(
      () => const WidgetImageRenderer().renderPng(
        widget: PlanShareImage(plan: plan, locale: const Locale('it')),
        width: PlanShareImage.logicalWidth,
        pixelRatio: 2,
      ),
    );

    final header = ByteData.sublistView(bytes!);
    expect(header.getUint32(16), PlanShareImage.logicalWidth * 2);
    // Quattro giorni non stanno in uno schermo: l'immagine è più alta.
    expect(header.getUint32(20), greaterThan(1200));
  });
}
