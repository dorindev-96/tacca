import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tacca/app/theme.dart';
import 'package:tacca/core/design/app_palette.dart';
import 'package:tacca/core/design/linear_icons.dart';
import 'package:tacca/core/widgets/home_tab_bar.dart';
import 'package:tacca/core/widgets/linear_icon.dart';

const _tabs = [
  HomeTab(icon: AppIcons.noteAdd, label: 'Schede'),
  HomeTab(icon: AppIcons.calendar, label: 'Storico'),
  HomeTab(icon: AppIcons.settings, label: 'Impostazioni'),
];

/// La barra con il suo stato: toccare una destinazione la seleziona, come fa
/// la shell del router.
class _Host extends StatefulWidget {
  const _Host({
    this.initialIndex = 0,
    this.tabs = _tabs,
    this.onDropStarted,
    this.onSelected,
  });

  final int initialIndex;
  final List<HomeTab> tabs;
  final VoidCallback? onDropStarted;
  final ValueChanged<int>? onSelected;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late int index = widget.initialIndex;

  void select(int value) => setState(() => index = value);

  @override
  Widget build(BuildContext context) {
    return HomeTabBar(
      tabs: widget.tabs,
      currentIndex: index,
      onDropStarted: widget.onDropStarted,
      onSelected: (value) {
        widget.onSelected?.call(value);
        select(value);
      },
    );
  }
}

void main() {
  Future<void> pumpBar(
    WidgetTester tester, {
    int initialIndex = 0,
    List<HomeTab> tabs = _tabs,
    VoidCallback? onDropStarted,
    ValueChanged<int>? onSelected,
    Brightness brightness = Brightness.light,
    bool disableAnimations = false,
    double? width,
  }) {
    Widget bar = _Host(
      initialIndex: initialIndex,
      tabs: tabs,
      onDropStarted: onDropStarted,
      onSelected: onSelected,
    );
    if (width != null) bar = SizedBox(width: width, child: bar);
    return tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.of(brightness),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: disableAnimations),
            child: Scaffold(body: Center(child: bar)),
          ),
        ),
      ),
    );
  }

  Finder tab(String label) => find.byKey(ValueKey('home-tab-$label'));

  /// Il rettangolo della barra sullo schermo.
  Rect barRect(WidgetTester tester) => tester.getRect(
    find.descendant(
      of: find.byType(HomeTabBar),
      matching: find.byType(Container),
    ),
  );

  /// L'ingombro della goccia, nelle coordinate della barra: è lo stesso
  /// tracciato che ritaglia icone ed etichette scure.
  ///
  /// Si misura camminando sul contorno e non con `Path.getBounds`, che
  /// include i punti di controllo delle curve: di una goccia stirata darebbe
  /// un rettangolo più grande di lei.
  Rect dropBounds(WidgetTester tester) {
    final clip = find.descendant(
      of: find.byType(HomeTabBar),
      matching: find.byType(ClipPath),
    );
    final path = tester
        .widget<ClipPath>(clip)
        .clipper!
        .getClip(tester.getSize(clip));
    Rect? bounds;
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d <= metric.length; d += 0.25) {
        final point = metric.getTangentForOffset(d)!.position;
        final dot = Rect.fromLTWH(point.dx, point.dy, 0, 0);
        bounds = bounds?.expandToInclude(dot) ?? dot;
      }
    }
    return bounds!;
  }

  /// Bordo sinistro delle icone chiare (lo strato di fondo), nelle coordinate
  /// della barra.
  List<double> iconLefts(WidgetTester tester) {
    final barLeft = barRect(tester).left;
    final icons = find.descendant(
      of: find.byType(HomeTabBar),
      matching: find.byType(LinearIcon),
    );
    // Due strati con le stesse icone: il primo è quello chiaro.
    return [
      for (var i = 0; i < _tabs.length; i++)
        tester.getTopLeft(icons.at(i)).dx - barLeft,
    ];
  }

  testWidgets('da ferma è la pillola del design: solo la tab attiva ha '
      "l'etichetta", (tester) async {
    await pumpBar(tester);

    expect(barRect(tester).size, const Size(340, 56));
    expect(find.text('Schede'), findsOneWidget);
    expect(find.text('Storico'), findsNothing);
    expect(find.text('Impostazioni'), findsNothing);

    // Pillola alta 36, appoggiata a 10 dal bordo, centrata in altezza.
    final drop = dropBounds(tester);
    expect(drop.left, closeTo(10, 0.01));
    expect(drop.height, closeTo(36, 0.01));
    expect(drop.center.dy, closeTo(28, 0.01));
    // Dentro: 16 · icona 24 · 16 · etichetta · 19.
    final label = tester.getRect(find.text('Schede'));
    final barLeft = barRect(tester).left;
    expect(iconLefts(tester)[0], closeTo(drop.left + 16, 0.01));
    expect(label.left - barLeft, closeTo(drop.left + 16 + 24 + 16, 0.01));
    expect(drop.right, closeTo(label.right - barLeft + 19, 1));
  });

  testWidgets('ogni destinazione ha un bersaglio largo almeno 48 e la '
      'semantica di un pulsante', (tester) async {
    final handle = tester.ensureSemantics();
    final selected = <int>[];
    await pumpBar(tester, onSelected: selected.add);

    for (final label in ['Schede', 'Storico', 'Impostazioni']) {
      final size = tester.getSize(tab(label));
      expect(size.width, greaterThanOrEqualTo(48), reason: label);
      expect(size.height, 56, reason: label);
    }
    expect(
      tester.getSemantics(tab('Schede')),
      matchesSemantics(
        label: 'Schede',
        isButton: true,
        isSelected: true,
        hasSelectedState: true,
        hasTapAction: true,
        hasFocusAction: true,
        isFocusable: true,
      ),
    );
    expect(
      tester.getSemantics(tab('Storico')),
      matchesSemantics(
        label: 'Storico',
        isButton: true,
        hasSelectedState: true,
        hasTapAction: true,
        hasFocusAction: true,
        isFocusable: true,
      ),
    );

    await tester.tap(tab('Impostazioni'));
    await tester.pumpAndSettle();
    await tester.tap(tab('Storico'));
    await tester.pumpAndSettle();
    expect(selected, [2, 1]);
    handle.dispose();
  });

  testWidgets('al cambio di destinazione la goccia si stira verso la nuova '
      'tab, poi la coda la raggiunge', (tester) async {
    await pumpBar(tester);
    final start = dropBounds(tester);

    await tester.tap(tab('Impostazioni'));
    await tester.pump();

    // In viaggio: la testa è già avanti, la coda è ancora indietro. Il lime
    // è un pezzo solo, più largo di una pillola e più sottile.
    await tester.pump(const Duration(milliseconds: 90));
    final stretched = dropBounds(tester);
    expect(stretched.left, lessThan(start.right));
    expect(stretched.right, greaterThan(start.right + 80));
    expect(stretched.width, greaterThan(start.width + 60));
    expect(stretched.height, lessThan(36));
    expect(find.byType(ClipPath), findsOneWidget);

    await tester.pumpAndSettle();
    final end = dropBounds(tester);
    // Arrivata: di nuovo una pillola alta 36, a 28 dal bordo destro.
    expect(end.height, closeTo(36, 0.01));
    expect(end.right, closeTo(340 - 28, 0.01));
    expect(end.left, greaterThan(start.left + 40));
    expect(find.text('Impostazioni'), findsOneWidget);
    expect(find.text('Schede'), findsNothing);
  });

  testWidgets("all'arrivo la goccia si schiaccia e torna: la coda supera il "
      'suo posto e rientra', (tester) async {
    await pumpBar(tester);
    await tester.tap(tab('Impostazioni'));
    await tester.pump();

    var narrowest = double.infinity;
    var tallest = 0.0;
    for (var ms = 0; ms < 620; ms += 20) {
      await tester.pump(const Duration(milliseconds: 20));
      final drop = dropBounds(tester);
      if (ms > 200) {
        narrowest = narrowest < drop.width ? narrowest : drop.width;
        tallest = tallest > drop.height ? tallest : drop.height;
      }
      // Mai fuori dalla barra, in nessun fotogramma.
      expect(drop.left, greaterThanOrEqualTo(0));
      expect(drop.right, lessThanOrEqualTo(340));
      expect(drop.top, greaterThanOrEqualTo(0));
      expect(drop.bottom, lessThanOrEqualTo(56));
    }
    await tester.pumpAndSettle();
    final rest = dropBounds(tester);
    expect(narrowest, lessThan(rest.width - 4));
    expect(tallest, greaterThan(37));
    expect(rest.height, closeTo(36, 0.01));
  });

  testWidgets('la goccia torna indietro specchiata', (tester) async {
    await pumpBar(tester, initialIndex: 2);
    final start = dropBounds(tester);

    await tester.tap(tab('Schede'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    final stretched = dropBounds(tester);
    // Verso sinistra la testa è il bordo sinistro.
    expect(stretched.left, lessThan(start.left - 40));
    expect(stretched.right, greaterThan(start.right - 20));
    expect(stretched.width, greaterThan(start.width + 30));
    expect(stretched.height, lessThan(36));

    await tester.pumpAndSettle();
    expect(dropBounds(tester).left, closeTo(10, 0.01));
  });

  testWidgets('un tocco a metà viaggio riparte da dove la goccia è, senza '
      'salti', (tester) async {
    await pumpBar(tester);
    await tester.tap(tab('Impostazioni'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final before = dropBounds(tester);
    final iconsBefore = iconLefts(tester);

    await tester.tap(tab('Storico'));
    await tester.pump();
    final after = dropBounds(tester);
    final iconsAfter = iconLefts(tester);

    expect(after.left, closeTo(before.left, 0.01));
    expect(after.right, closeTo(before.right, 0.01));
    expect(after.height, closeTo(before.height, 0.01));
    for (var i = 0; i < _tabs.length; i++) {
      expect(iconsAfter[i], closeTo(iconsBefore[i], 0.01));
    }

    await tester.pumpAndSettle();
    expect(find.text('Storico'), findsOneWidget);
    expect(find.text('Impostazioni'), findsNothing);
    expect(dropBounds(tester).height, closeTo(36, 0.01));
  });

  testWidgets('la partenza si annuncia una volta sola, nel fotogramma in cui '
      'la goccia parte', (tester) async {
    var starts = 0;
    await pumpBar(tester, onDropStarted: () => starts++);
    expect(starts, 0);

    await tester.tap(tab('Storico'));
    await tester.pump();
    expect(starts, 1, reason: 'il suono parte con la goccia, non dopo');
    expect(tester.hasRunningAnimations, isTrue);

    await tester.pumpAndSettle();
    expect(starts, 1);

    // Ri-toccare la tab attiva non muove niente.
    await tester.tap(tab('Storico'));
    await tester.pumpAndSettle();
    expect(starts, 1);
  });

  testWidgets('il tocco non fa il click di sistema: il suono è solo il plop', (
    tester,
  ) async {
    await pumpBar(tester);
    final inkWells = tester.widgetList<InkWell>(
      find.descendant(
        of: find.byType(HomeTabBar),
        matching: find.byType(InkWell),
      ),
    );
    expect(inkWells, isNotEmpty);
    expect(inkWells.every((w) => w.enableFeedback == false), isTrue);
  });

  testWidgets('con le animazioni disattivate dal sistema la pillola si '
      'sposta e basta', (tester) async {
    var starts = 0;
    await pumpBar(
      tester,
      disableAnimations: true,
      onDropStarted: () => starts++,
    );

    await tester.tap(tab('Impostazioni'));
    await tester.pump();

    expect(starts, 1);
    expect(tester.hasRunningAnimations, isFalse);
    final drop = dropBounds(tester);
    expect(drop.height, closeTo(36, 0.01));
    expect(drop.right, closeTo(340 - 28, 0.01));
    expect(find.text('Impostazioni'), findsOneWidget);
  });

  testWidgets("un'etichetta troppo lunga si tronca dentro la barra, anche "
      'su uno schermo stretto', (tester) async {
    const tabs = [
      HomeTab(icon: AppIcons.noteAdd, label: 'Träningsprogram och scheman'),
      HomeTab(icon: AppIcons.calendar, label: 'Historik'),
      HomeTab(icon: AppIcons.settings, label: 'Inställningar'),
    ];
    await pumpBar(tester, tabs: tabs, width: 280);

    expect(tester.takeException(), isNull);
    final bar = barRect(tester);
    expect(bar.width, 280);
    // La pillola lascia alle altre due tab i loro 40 punti.
    final drop = dropBounds(tester);
    expect(drop.left, closeTo(10, 0.01));
    expect(drop.right, closeTo(280 - 28 - 40 - 40, 0.01));
    final label = tester.getRect(find.text(tabs[0].label));
    expect(label.right - bar.left, lessThanOrEqualTo(drop.right - 19 + 0.01));

    await tester.tap(tab('Inställningar'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(dropBounds(tester).right, closeTo(280 - 28, 0.01));
  });

  for (final brightness in Brightness.values) {
    testWidgets('colori nel tema ${brightness.name}: lime uno solo, scuro '
        'sopra il lime e chiaro sul fondo, anche in viaggio', (tester) async {
      final palette = AppPalette.of(brightness);
      await pumpBar(tester, brightness: brightness);

      Color iconColor(int index) => tester
          .widget<LinearIcon>(
            find
                .descendant(
                  of: find.byType(HomeTabBar),
                  matching: find.byType(LinearIcon),
                )
                .at(index),
          )
          .color!;

      void expectColors() {
        // Strato di fondo, poi lo strato ritagliato sulla goccia.
        for (var i = 0; i < _tabs.length; i++) {
          expect(iconColor(i), palette.onInkSurface);
          expect(iconColor(_tabs.length + i), palette.onLime);
        }
        final paint = find.descendant(
          of: find.byType(HomeTabBar),
          // Anche le icone sono `CustomPaint`: la goccia è quello col suo
          // painter.
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is CustomPaint &&
                widget.painter.runtimeType.toString() == '_DropPainter',
          ),
        );
        expect(
          paint,
          paints..path(color: palette.lime, style: PaintingStyle.fill),
        );
      }

      expectColors();
      expect(
        tester.widget<Text>(find.text('Schede')).style!.color,
        palette.onLime,
      );

      await tester.tap(tab('Storico'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expectColors();
      await tester.pumpAndSettle();
      expectColors();
    });
  }
}
