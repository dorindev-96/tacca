import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../design/app_radius.dart';
import '../design/app_spacing.dart';
import '../design/linear_icons.dart';
import '../design/theme_context.dart';
import 'linear_icon.dart';

/// Una destinazione della [HomeTabBar].
class HomeTab {
  const HomeTab({required this.icon, required this.label});

  final LinearIconData icon;
  final String label;
}

/// Tab bar flottante: 340×56, raggio 32, fondo pieno, con la destinazione
/// attiva in una pillola lime che porta anche l'etichetta.
///
/// Solo la tab attiva è etichettata: è quello che rende leggibile una barra
/// alta 56 senza schiacciarci dentro tre testi. Le altre restano icone, e
/// l'etichetta arriva comunque all'accessibilità via [Semantics].
///
/// La barra è il motivo per cui `inkSurface` non si schiarisce nel tema
/// scuro: la pillola attiva è lime, e il lime su un fondo quasi bianco non si
/// distingue più (1,1:1). Vedi [AppPalette].
///
/// **La pillola è una goccia.** Al cambio di destinazione non salta: la testa
/// parte subito verso la nuova tab, la coda resta attaccata un istante e il
/// lime si stira e si assottiglia nel mezzo; poi la coda si stacca, raggiunge
/// la testa, la goccia si schiaccia appena all'arrivo e si assesta. Il lime
/// resta uno solo per tutto il viaggio (è la regola della palette): non c'è
/// mai una pillola che svanisce mentre un'altra compare.
///
/// Perché regga, la barra non è più una `Row` di widget ma tre strati
/// disegnati sulla stessa geometria ([_BarMetrics]): le icone chiare, la
/// goccia, e sopra le stesse icone — più le etichette — scure e **ritagliate
/// sulla goccia**. È il ritaglio a cambiare colore a un'icona esattamente dove
/// il lime la copre, invece di sfumarla da un colore all'altro mentre la
/// goccia è ancora a metà strada.
class HomeTabBar extends StatefulWidget {
  const HomeTabBar({
    required this.tabs,
    required this.currentIndex,
    required this.onSelected,
    this.onDropLanded,
    super.key,
  });

  final List<HomeTab> tabs;
  final int currentIndex;
  final ValueChanged<int> onSelected;

  /// Chiamata una volta per ogni cambio di destinazione, nel momento in cui
  /// la goccia tocca la nuova tab: è l'aggancio del suono, che deve cadere
  /// sull'arrivo e non sul tocco. Con le animazioni disattivate dal sistema
  /// la goccia non viaggia e la chiamata è immediata.
  final VoidCallback? onDropLanded;

  static const double _width = 340;

  /// Altezza della barra: le pagine della shell la sommano allo spazio che
  /// lasciano in fondo alle liste.
  static const double height = 56;

  /// Durata dell'intero spostamento, assestamento compreso. Il viaggio vero
  /// sta nel primo terzo: il resto è la goccia che smette di tremare.
  static const Duration dropDuration = Duration(milliseconds: 620);

  @override
  State<HomeTabBar> createState() => _HomeTabBarState();
}

class _HomeTabBarState extends State<HomeTabBar>
    with SingleTickerProviderStateMixin {
  /// Punto dell'animazione in cui la testa ha raggiunto la destinazione.
  static const double _landingPoint = 0.3;

  /// La testa: parte subito e arriva in un quarto della durata, con un filo
  /// di rimbalzo.
  static const Curve _headCurve = _SpringCurve(damping: 0.75, frequency: 14);

  /// La coda: resta attaccata, poi scatta, supera di poco l'arrivo (è lo
  /// schiacciamento della goccia) e torna.
  static const Curve _tailCurve = _SpringCurve(
    damping: 0.62,
    frequency: 10,
    delay: 0.1,
  );

  /// Icone ed etichette: si spostano mentre la goccia viaggia e sono già al
  /// loro posto quando la coda arriva. Il resto della durata è solo la goccia
  /// che si assesta, e lì dentro non deve più scivolare niente.
  static const Curve _layoutCurve = Interval(
    0,
    0.45,
    curve: Curves.fastOutSlowIn,
  );

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: HomeTabBar.dropDuration,
    value: 1,
  )..addListener(_maybeLand);

  /// Quanto ogni tab era "attiva" (0–1) alla partenza dello spostamento in
  /// corso. Non è per forza uno 0/1 netto: un tocco a metà viaggio riparte
  /// da dove le cose stanno.
  late List<double> _amountsFrom = _restAmounts(widget.currentIndex);

  /// Bordi della goccia alla partenza, e quelli dell'ultimo fotogramma
  /// disegnato (che diventano la partenza del prossimo spostamento).
  _DropEdges? _edgesFrom;
  _DropEdges? _edgesDrawn;

  bool _landed = true;

  List<double> _restAmounts(int index) => [
    for (var i = 0; i < widget.tabs.length; i++) i == index ? 1.0 : 0.0,
  ];

  List<double> _amountsAt(double progress, int target) {
    final t = _layoutCurve.transform(progress);
    return [
      for (var i = 0; i < _amountsFrom.length; i++)
        lerpDouble(_amountsFrom[i], i == target ? 1.0 : 0.0, t)!,
    ];
  }

  @override
  void didUpdateWidget(HomeTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.tabs.length != oldWidget.tabs.length) {
      // Destinazioni diverse: nessun viaggio ha più senso, si riparte fermi.
      _amountsFrom = _restAmounts(widget.currentIndex);
      _edgesFrom = null;
      _landed = true;
      _controller.value = 1;
      return;
    }
    if (widget.currentIndex == oldWidget.currentIndex) return;

    _amountsFrom = _amountsAt(_controller.value, oldWidget.currentIndex);
    _edgesFrom = _edgesDrawn;
    _landed = false;

    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
      _maybeLand();
    } else {
      _controller.forward(from: 0);
    }
  }

  void _maybeLand() {
    if (_landed || _controller.value < _landingPoint) return;
    _landed = true;
    widget.onDropLanded?.call();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Lo stile si risolve qui una volta, com'è dentro un `Text`, e lo stesso
    // identico stile misura l'etichetta e la disegna: una misura fatta con
    // uno stile appena diverso taglierebbe l'ultima lettera.
    var labelStyle = DefaultTextStyle.of(
      context,
    ).style.merge(context.type.meta).copyWith(color: colors.onLime);
    if (MediaQuery.boldTextOf(context)) {
      labelStyle = labelStyle.copyWith(fontWeight: FontWeight.bold);
    }

    // Una larghezza fissa sotto `Center` si stringe da sé a quella
    // disponibile: sugli schermi più stretti di 340 la barra li riempie.
    return Center(
      child: Container(
        width: HomeTabBar._width,
        height: HomeTabBar.height,
        decoration: BoxDecoration(
          color: colors.inkSurface,
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.xl)),
          boxShadow: context.chrome.floating,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final metrics = _BarMetrics.measure(
              context,
              barWidth: constraints.maxWidth,
              labels: [for (final tab in widget.tabs) tab.label],
              labelStyle: labelStyle,
            );
            return RepaintBoundary(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => _frame(context, metrics, labelStyle),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _frame(
    BuildContext context,
    _BarMetrics metrics,
    TextStyle labelStyle,
  ) {
    final colors = context.colors;
    final progress = _controller.value;
    final amounts = _amountsAt(progress, widget.currentIndex);
    final lefts = metrics.tabLefts(amounts);

    // La goccia: testa e coda vanno ognuna per conto suo dalla partenza alla
    // pillola d'arrivo, ed è lo scarto fra le due a stirarla.
    final rest = metrics.pillAt(widget.currentIndex);
    final from = _edgesFrom ?? rest;
    final forward = rest.center >= from.center;
    final head = _headCurve.transform(progress);
    final tail = _tailCurve.transform(progress);
    final edges = _DropEdges(
      lerpDouble(from.left, rest.left, forward ? tail : head)!,
      lerpDouble(from.right, rest.right, forward ? head : tail)!,
    );
    _edgesDrawn = edges;

    final drop = _dropPath(
      edges,
      // Lo scarto si misura contro la larghezza che la pillola avrebbe da
      // ferma in questo istante, non contro quella di partenza: così un
      // tocco a metà viaggio non cambia forma alla goccia di colpo.
      strain: edges.width - metrics.naturalPillWidth(amounts),
      forward: forward,
    );

    final slots = metrics.slots(widget.currentIndex);
    const iconTop = (HomeTabBar.height - _BarMetrics.icon) / 2;

    Widget icons(Color color) => Stack(
      children: [
        for (var i = 0; i < widget.tabs.length; i++)
          Positioned(
            left: lefts[i] + metrics.iconInset(amounts[i]),
            top: iconTop,
            child: LinearIcon(widget.tabs[i].icon, color: color),
          ),
      ],
    );

    return Stack(
      children: [
        // 1. Le icone come stanno sul fondo pieno.
        Positioned.fill(
          child: IgnorePointer(
            child: ExcludeSemantics(child: icons(colors.onInkSurface)),
          ),
        ),
        // 2. La goccia.
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _DropPainter(path: drop, color: colors.lime),
            ),
          ),
        ),
        // 3. Le stesse icone, e le etichette, come stanno sul lime: si
        //    vedono solo dove la goccia c'è.
        Positioned.fill(
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: ClipPath(
                clipper: _DropClipper(drop),
                child: Stack(
                  children: [
                    Positioned.fill(child: icons(colors.onLime)),
                    for (var i = 0; i < widget.tabs.length; i++)
                      if (amounts[i] > 0.01)
                        Positioned(
                          left:
                              lefts[i] +
                              metrics.iconInset(amounts[i]) +
                              _BarMetrics.icon +
                              _BarMetrics.labelGap,
                          top: 0,
                          bottom: 0,
                          width: metrics.labelSlot(i),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              widget.tabs[i].label,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              // L'etichetta c'è solo a pillola quasi fatta:
                              // quella di partenza sparisce prima che il
                              // collo le si stringa sopra, quella d'arrivo
                              // compare quando la goccia è ormai lì.
                              style: labelStyle.copyWith(
                                color: colors.onLime.withValues(
                                  alpha: math.pow(amounts[i], 4).toDouble(),
                                ),
                              ),
                            ),
                          ),
                        ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // 4. I bersagli: fermi sulla disposizione d'arrivo, e larghi quanto
        //    lo spazio fra una tab e l'altra — un'icona da 24 non è un
        //    bersaglio (RNF-04).
        for (var i = 0; i < widget.tabs.length; i++)
          Positioned(
            left: slots[i],
            width: slots[i + 1] - slots[i],
            top: 0,
            bottom: 0,
            child: Semantics(
              key: ValueKey('home-tab-${widget.tabs[i].label}'),
              button: true,
              selected: i == widget.currentIndex,
              label: widget.tabs[i].label,
              // Niente velo dei tocchi: il `Material` più vicino è quello
              // della shell, che disegna l'inchiostro *sotto* il fondo pieno
              // della barra. Sarebbe un'animazione a ogni tocco che nessuno
              // vede; la risposta al tocco è la goccia che parte.
              child: InkWell(
                onTap: () => widget.onSelected(i),
                splashFactory: NoSplash.splashFactory,
                highlightColor: Colors.transparent,
                hoverColor: Colors.transparent,
                focusColor: Colors.transparent,
              ),
            ),
          ),
      ],
    );
  }

  /// Il contorno della goccia fra i due [edges].
  ///
  /// Da ferma è la pillola del design. Stirata ([strain] > 0) è due teste
  /// tonde unite da un collo che si stringe: grande quella che va avanti,
  /// più piccola quella che resta indietro. Schiacciata ([strain] < 0, la
  /// coda che arriva di slancio) si gonfia di un paio di punti.
  Path _dropPath(
    _DropEdges edges, {
    required double strain,
    required bool forward,
  }) {
    const cy = HomeTabBar.height / 2;
    const r = _BarMetrics.pillHeight / 2;

    final stretch = (strain / 90).clamp(0.0, 1.0);
    final squash = (-strain / 14).clamp(0.0, 1.0);
    final headRadius = r - 1.5 * stretch + 2.5 * squash;
    final tailRadius = r - 6 * stretch + 2.5 * squash;

    var leftRadius = forward ? tailRadius : headRadius;
    var rightRadius = forward ? headRadius : tailRadius;
    // Due cerchi devono starci: una goccia più stretta di così non esiste.
    final fit = math.min(1.0, edges.width / (leftRadius + rightRadius));
    leftRadius *= fit;
    rightRadius *= fit;

    if (stretch < 0.001 && (leftRadius - rightRadius).abs() < 0.001) {
      return Path()..addRRect(
        RRect.fromLTRBR(
          edges.left,
          cy - leftRadius,
          edges.right,
          cy + leftRadius,
          Radius.circular(leftRadius),
        ),
      );
    }

    final leftCenter = edges.left + leftRadius;
    final rightCenter = edges.right - rightRadius;

    // I punti in cui il collo lascia le due teste scivolano verso l'interno
    // man mano che la goccia si stira, e il collo ne esce tangente: nessuno
    // spigolo, in nessun punto del viaggio.
    final angle = math.pi / 2 - 0.55 * stretch;
    final sin = math.sin(angle);
    final cos = math.cos(angle);
    final ax = leftCenter + leftRadius * cos;
    final ay = leftRadius * sin;
    final bx = rightCenter - rightRadius * cos;
    final by = rightRadius * sin;

    // Metà spessore del collo nel punto più stretto: da quello delle teste
    // fino a 7,5 punti. La lunghezza delle maniglie è ciò che lo ottiene.
    final neck = lerpDouble((ay + by) / 2, 7.5, stretch)!;
    final span = math.max(0.0, bx - ax);
    final handle = cos < 0.001
        ? span * 0.4
        : math.min(span * 0.45, ((ay + by) / 2 - neck) * 8 / (6 * cos));
    final hx = handle * sin;
    final hy = handle * cos;

    return Path()
      ..moveTo(ax, cy - ay)
      ..cubicTo(ax + hx, cy - ay + hy, bx - hx, cy - by + hy, bx, cy - by)
      ..arcToPoint(
        Offset(bx, cy + by),
        radius: Radius.circular(rightRadius),
        largeArc: true,
      )
      ..cubicTo(bx - hx, cy + by - hy, ax + hx, cy + ay - hy, ax, cy + ay)
      ..arcToPoint(
        Offset(ax, cy - ay),
        radius: Radius.circular(leftRadius),
        largeArc: true,
      )
      ..close();
  }
}

/// Bordo sinistro e destro della goccia, nelle coordinate della barra.
class _DropEdges {
  const _DropEdges(this.left, this.right);

  final double left;
  final double right;

  double get width => right - left;
  double get center => (left + right) / 2;
}

/// Le misure della barra, e dove sta ogni cosa per una data ripartizione
/// dell'"essere attiva" fra le tab.
///
/// La disposizione è una funzione sola di quelle quantità (0 = solo icona,
/// 1 = pillola con l'etichetta): da ferma ne vale una sola, in viaggio la
/// partenza cala mentre l'arrivo cresce, e le tab intermedie si spostano di
/// conseguenza. Non esistono due disposizioni fra cui sfumare.
class _BarMetrics {
  const _BarMetrics._({
    required this.barWidth,
    required this.pillWidths,
    required this.count,
  });

  /// Misura le etichette con lo stile con cui verranno disegnate.
  factory _BarMetrics.measure(
    BuildContext context, {
    required double barWidth,
    required List<String> labels,
    required TextStyle labelStyle,
  }) {
    final painter = TextPainter(
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
      maxLines: 1,
    );
    final inner = barWidth - padLeft - padRight;
    // Solo la tab attiva porta l'etichetta, quindi solo lei può diventare
    // troppo larga: le si lascia ciò che avanza dalle altre, e l'etichetta
    // si tronca.
    final maxPill = math.max(
      collapsedWidth,
      inner - collapsedWidth * (labels.length - 1),
    );
    final widths = <double>[];
    for (final label in labels) {
      painter
        ..text = TextSpan(text: label, style: labelStyle)
        ..layout();
      final natural =
          pillPadLeft +
          icon +
          labelGap +
          painter.width.ceilToDouble() +
          pillPadRight;
      widths.add(math.min(natural, maxPill));
    }
    painter.dispose();
    return _BarMetrics._(
      barWidth: barWidth,
      pillWidths: widths,
      count: labels.length,
    );
  }

  /// Margini della barra: asimmetrici come nel file di design, dove a
  /// sinistra si appoggia la pillola e a destra un'icona con la sua aria.
  static const double padLeft = AppSpacing.sm + 2;
  static const double padRight = AppSpacing.xl + AppSpacing.xs;

  static const double icon = 24;
  static const double pillHeight = 36;

  /// Tab chiusa: l'icona con 8 punti per parte.
  static const double collapsedInset = AppSpacing.sm;
  static const double collapsedWidth = icon + 2 * collapsedInset;

  /// Tab aperta: 16 · icona · 16 · etichetta · 19.
  static const double pillPadLeft = AppSpacing.lg;
  static const double labelGap = AppSpacing.lg;
  static const double pillPadRight = AppSpacing.card - 1;

  final double barWidth;
  final int count;

  /// Larghezza della pillola di ogni tab quando è lei quella attiva.
  final List<double> pillWidths;

  double _tabWidth(int i, double amount) =>
      lerpDouble(collapsedWidth, pillWidths[i], amount)!;

  /// Distanza dell'icona dal bordo sinistro della sua tab.
  double iconInset(double amount) =>
      lerpDouble(collapsedInset, pillPadLeft, amount)!;

  /// Spazio riservato all'etichetta della tab [i] dentro la sua pillola.
  double labelSlot(int i) =>
      math.max(0, pillWidths[i] - pillPadLeft - icon - labelGap - pillPadRight);

  /// Bordo sinistro di ogni tab: le tab si spartiscono lo spazio che avanza
  /// in parti uguali, come farebbe una `Row` con `spaceBetween`.
  List<double> tabLefts(List<double> amounts) {
    var used = 0.0;
    for (var i = 0; i < count; i++) {
      used += _tabWidth(i, amounts[i]);
    }
    final inner = barWidth - padLeft - padRight;
    final gap = count > 1 ? math.max(0.0, inner - used) / (count - 1) : 0.0;

    final lefts = <double>[];
    var x = padLeft;
    for (var i = 0; i < count; i++) {
      lefts.add(x);
      x += _tabWidth(i, amounts[i]) + gap;
    }
    return lefts;
  }

  List<double> _restAmounts(int index) => [
    for (var i = 0; i < count; i++) i == index ? 1.0 : 0.0,
  ];

  /// La pillola della tab [index] quando è attiva e tutto è fermo.
  _DropEdges pillAt(int index) {
    final left = tabLefts(_restAmounts(index))[index];
    return _DropEdges(left, left + pillWidths[index]);
  }

  /// Larghezza che la pillola avrebbe, da ferma, con questa ripartizione.
  double naturalPillWidth(List<double> amounts) {
    var width = 0.0;
    var total = 0.0;
    for (var i = 0; i < count; i++) {
      width += amounts[i] * pillWidths[i];
      total += amounts[i];
    }
    return total > 0 ? width / total : collapsedWidth;
  }

  /// Confini dei bersagli con la tab [index] attiva: `count + 1` ascisse, a
  /// metà strada fra una tab e la successiva.
  List<double> slots(int index) {
    final amounts = _restAmounts(index);
    final lefts = tabLefts(amounts);
    return [
      0,
      for (var i = 1; i < count; i++)
        (lefts[i - 1] + _tabWidth(i - 1, amounts[i - 1]) + lefts[i]) / 2,
      barWidth,
    ];
  }
}

class _DropPainter extends CustomPainter {
  const _DropPainter({required this.path, required this.color});

  final Path path;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(_DropPainter oldDelegate) =>
      oldDelegate.path != path || oldDelegate.color != color;
}

class _DropClipper extends CustomClipper<Path> {
  const _DropClipper(this.path);

  final Path path;

  @override
  Path getClip(Size size) => path;

  @override
  bool shouldReclip(_DropClipper oldClipper) => oldClipper.path != path;
}

/// La risposta di una molla sottosmorzata a uno scatto, da 0 a 1: parte da
/// ferma, supera l'arrivo di poco e ci torna.
///
/// È la differenza fra una pillola che scorre e una goccia: una curva di
/// Bézier arriva e si ferma, una molla arriva, sbaglia e si corregge. Con
/// [delay] la partenza aspetta, ed è così che la coda resta attaccata mentre
/// la testa è già in viaggio.
class _SpringCurve extends Curve {
  const _SpringCurve({
    required this.damping,
    required this.frequency,
    this.delay = 0,
  });

  /// Rapporto di smorzamento (< 1): più è basso, più rimbalza.
  final double damping;

  /// Pulsazione naturale, in radianti sull'intera durata.
  final double frequency;

  /// Frazione della durata in cui la molla resta ferma.
  final double delay;

  double _response(double u) {
    final damped = frequency * math.sqrt(1 - damping * damping);
    return 1 -
        math.exp(-damping * frequency * u) *
            (math.cos(damped * u) +
                damping * frequency / damped * math.sin(damped * u));
  }

  @override
  double transformInternal(double t) {
    if (t <= delay) return 0;
    final u = (t - delay) / (1 - delay);
    // Una molla non è mai ferma del tutto: il residuo si spalma sulla durata
    // perché la curva chiuda a 1 esatto.
    return _response(u) + (1 - _response(1)) * u;
  }
}
