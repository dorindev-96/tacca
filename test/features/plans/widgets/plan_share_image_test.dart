import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tacca/core/design/app_palette.dart';
import 'package:tacca/data/entities/block.dart';
import 'package:tacca/data/entities/exercise.dart';
import 'package:tacca/data/entities/workout_day.dart';
import 'package:tacca/data/entities/workout_plan.dart';
import 'package:tacca/features/plans/widgets/plan_day_view.dart';
import 'package:tacca/features/plans/widgets/plan_share_image.dart';
import 'package:tacca/services/images/widget_image_renderer.dart';

/// L'immagine da mandare in chat: c'è dentro **tutta** la scheda, firmata, e
/// quando la scheda è lunga si divide in pagine che restano nitide invece di
/// diventare una striscia che la chat rimpicciolisce.
void main() {
  WorkoutPlan seedPlan({
    int days = 2,
    int exercisesPerDay = 1,
    String? notes = 'Da integrare con camminate nei giorni di stop',
    String? description,
  }) {
    final now = DateTime(2026, 1, 1);
    final plan = WorkoutPlan(
      name: 'Scheda 2 Giorni',
      notes: notes,
      description: description,
      createdAt: now,
      updatedAt: now,
    )..id = 1;

    for (var d = 0; d < days; d++) {
      final day = WorkoutDay(label: 'Giorno ${d + 1}', sortOrder: d)
        ..id = d + 1;
      final block = Block.ofType(BlockType.standard, sortOrder: 0);
      for (var e = 0; e < exercisesPerDay; e++) {
        block.exercises.add(
          Exercise(
            name: exercisesPerDay == 1
                ? 'Back Squat al Multipower ${d + 1}'
                : 'Esercizio ${d + 1}.${e + 1}',
            sets: 3,
            reps: '8-10',
            restSeconds: 120,
            sortOrder: e,
          ),
        );
      }
      day.blocks.add(block);
      plan.days.add(day);
    }
    return plan;
  }

  PlanShareImage imageOf(
    WorkoutPlan plan, {
    Brightness brightness = Brightness.light,
  }) => PlanShareImage(
    plan: plan,
    locale: const Locale('it'),
    brightness: brightness,
  );

  /// Le pagine come le impagina il servizio di condivisione: misurate davvero,
  /// fuori schermo, alla larghezza dell'immagine.
  List<Widget> pagesOf(PlanShareImage image) => const WidgetImageRenderer()
      .measure(width: image.pageWidth, body: image.paginate);

  double heightOf(Widget page) => const WidgetImageRenderer().measure(
    width: PlanShareImage.logicalWidth,
    body: (measure) => measure(page),
  );

  Future<void> pumpPage(WidgetTester tester, Widget page) async {
    // La pagina è alta quanto serve: la finestra di test di default la
    // taglierebbe e farebbe scattare l'overflow.
    tester.view.physicalSize = const Size(PlanShareImage.logicalWidth, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(Align(alignment: Alignment.topCenter, child: page));
    await tester.pumpAndSettle();
  }

  /// I testi di tutte le pagine, pagina per pagina.
  Future<List<List<String>>> textsOf(
    WidgetTester tester,
    List<Widget> pages,
  ) async {
    final result = <List<String>>[];
    for (final page in pages) {
      await pumpPage(tester, page);
      result.add([
        for (final text in tester.widgetList<Text>(find.byType(Text)))
          if (text.data != null) text.data!,
      ]);
    }
    return result;
  }

  testWidgets('una scheda corta è un\'immagine sola, con tutti i giorni', (
    tester,
  ) async {
    final pages = pagesOf(imageOf(seedPlan()));
    expect(pages, hasLength(1));

    await pumpPage(tester, pages.single);
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

  testWidgets('l\'immagine è firmata, e una pagina sola non si numera', (
    tester,
  ) async {
    await pumpPage(tester, pagesOf(imageOf(seedPlan())).single);

    expect(find.text('Tacca'), findsOneWidget);
    expect(find.textContaining('Pagina'), findsNothing);
  });

  testWidgets('lo stato della scheda resta nell\'app, non nell\'immagine', (
    tester,
  ) async {
    final plan = seedPlan()..isActive = true;
    await pumpPage(tester, pagesOf(imageOf(plan)).single);

    // "In uso" è l'unico lime del dettaglio e dice "questa, adesso": a chi
    // riceve l'immagine non direbbe niente.
    expect(find.text('In uso'), findsNothing);
  });

  testWidgets('si condivide il tema in cui si guarda la scheda', (
    tester,
  ) async {
    await pumpPage(
      tester,
      pagesOf(imageOf(seedPlan(), brightness: Brightness.dark)).single,
    );

    final background = tester.widget<ColoredBox>(find.byType(ColoredBox).first);
    expect(background.color, AppPalette.dark.background);
  });

  group('una scheda lunga', () {
    // Quattro giorni da dodici esercizi: una striscia sola sarebbe alta
    // diversi schermi, cioè proprio il caso che la chat rimpicciolisce.
    WorkoutPlan longPlan() => seedPlan(days: 4, exercisesPerDay: 12);

    testWidgets('si divide in pagine, nessuna più alta del massimo', (
      tester,
    ) async {
      final pages = pagesOf(imageOf(longPlan()));

      expect(pages.length, greaterThan(1));
      for (final page in pages) {
        expect(heightOf(page), lessThanOrEqualTo(PlanShareImage.maxPageHeight));
      }
    });

    testWidgets('ogni esercizio finisce in una pagina sola, in ordine', (
      tester,
    ) async {
      final pages = pagesOf(imageOf(longPlan()));
      final names = [
        for (final texts in await textsOf(tester, pages))
          ...texts.where((text) => text.startsWith('Esercizio ')),
      ];

      expect(names, [
        for (var d = 1; d <= 4; d++)
          for (var e = 1; e <= 12; e++) 'Esercizio $d.$e',
      ]);
    });

    testWidgets('ogni pagina è firmata e dice a che punto si è', (
      tester,
    ) async {
      final pages = pagesOf(imageOf(longPlan()));
      final texts = await textsOf(tester, pages);

      for (var i = 0; i < pages.length; i++) {
        expect(texts[i], contains('Tacca'));
        expect(texts[i], contains('Pagina ${i + 1} di ${pages.length}'));
        // Anche le pagine dopo la prima dicono di che scheda sono: ognuna
        // viaggia da sola in una chat.
        expect(texts[i], contains('Scheda 2 Giorni'));
      }
      // Il titolo grande e il conteggio dei giorni solo sulla prima.
      expect(texts.first, contains('4 giorni'));
      expect(texts.skip(1).expand((t) => t), isNot(contains('4 giorni')));
    });

    testWidgets('la pagina che riprende un giorno a metà ne ripete '
        'l\'etichetta e il tipo di blocco', (tester) async {
      final pages = pagesOf(imageOf(seedPlan(days: 2, exercisesPerDay: 20)));
      final texts = await textsOf(tester, pages);

      // Venti esercizi non stanno in una pagina: il Giorno 1 continua sulla
      // seconda, che lo dice invece di partire da una card senza nome.
      expect(texts[0], contains('Giorno 1'));
      expect(texts[0], isNot(contains('Esercizio 1.20')));
      expect(texts[1], contains('Giorno 1'));
      expect(texts[1], contains('Standard'));
    });

    testWidgets('un blocco spezzato continua la numerazione', (tester) async {
      final pages = pagesOf(
        imageOf(seedPlan(days: 1, exercisesPerDay: 30, notes: null)),
      );
      expect(pages.length, greaterThan(1));

      final positions = <int>[];
      for (final page in pages) {
        await pumpPage(tester, page);
        positions.addAll(
          tester
              .widgetList<ExercisePosition>(find.byType(ExercisePosition))
              .map((widget) => widget.position),
        );
      }
      expect(positions, [for (var i = 1; i <= 30; i++) i]);
    });
  });

  testWidgets('un testo libero lungo si spezza per righe, senza perderne '
      'nessuna', (tester) async {
    final now = DateTime(2026, 1, 1);
    final plan = WorkoutPlan(
      name: 'Trascrizione',
      createdAt: now,
      updatedAt: now,
    )..id = 1;
    final day = WorkoutDay(label: 'Giorno 1')..id = 1;
    day.blocks.add(
      Block.ofType(BlockType.freeText)
        ..freeTextContent = [
          for (var i = 1; i <= 120; i++) 'Riga numero $i',
        ].join('\n'),
    );
    plan.days.add(day);

    final pages = pagesOf(imageOf(plan));
    expect(pages.length, greaterThan(1));

    final lines = [
      for (final texts in await textsOf(tester, pages))
        for (final text in texts)
          if (text.startsWith('Riga numero')) ...text.split('\n'),
    ];
    expect(lines, [for (var i = 1; i <= 120; i++) 'Riga numero $i']);
  });

  testWidgets('un pezzo più alto di una pagina va da solo e non si perde', (
    tester,
  ) async {
    final plan = seedPlan(days: 1, notes: null);
    final squat = plan.days.first.blocks.first.exercises.first;
    squat.notes = List.filled(150, 'Scendere lenti.').join('\n');

    final pages = pagesOf(imageOf(plan));
    final texts = await textsOf(tester, pages);

    expect(
      texts.expand((t) => t).where((t) => t == 'Back Squat al Multipower 1'),
      hasLength(1),
    );
    // La pagina che lo contiene è più alta delle altre: si perde in
    // definizione, non in contenuto.
    expect(
      pages.map(heightOf).any((h) => h > PlanShareImage.maxPageHeight),
      isTrue,
    );
  });

  testWidgets('si disegna anche senza un MaterialApp sopra', (tester) async {
    final image = imageOf(seedPlan(days: 4));
    final pages = pagesOf(image);

    final Uint8List? bytes = await tester.runAsync(
      () => const WidgetImageRenderer().renderPng(
        widget: pages.first,
        width: image.pageWidth,
        pixelRatio: 2,
      ),
    );

    final header = ByteData.sublistView(bytes!);
    expect(header.getUint32(16), PlanShareImage.logicalWidth * 2);
    // La pagina è alta quanto il suo contenuto: più di uno schermo di test,
    // mai più del massimo.
    expect(header.getUint32(20), greaterThan(1200));
    expect(
      header.getUint32(20),
      lessThanOrEqualTo(PlanShareImage.maxPageHeight * 2),
    );
  });
}
