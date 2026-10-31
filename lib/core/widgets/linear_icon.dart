import 'package:flutter/material.dart';

import '../design/linear_icons.dart';

/// Disegna un glifo di [AppIcons] alla dimensione richiesta, riempito con il
/// colore corrente.
///
/// I tracciati sono SVG con soli comandi assoluti `M`/`L`/`C`/`Z` (è tutto
/// quello che il set "Linear Icons" usa): il parser qui sotto copre quelli e
/// nient'altro di proposito — un parser SVG generico sarebbe codice non
/// verificato per casi che non esistono nel progetto.
class LinearIcon extends StatelessWidget {
  const LinearIcon(this.icon, {this.size = 24, this.color, super.key});

  final LinearIconData icon;
  final double size;

  /// Null = il colore dell'[IconTheme] in cui il glifo si trova, esattamente
  /// come `currentColor` nell'SVG di origine.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    Widget glyph = CustomPaint(
      size: Size.square(size),
      painter: _LinearIconPainter(
        icon: icon,
        color: color ?? _currentColor(context),
      ),
    );

    if (icon.quarterTurns != 0) {
      glyph = RotatedBox(quarterTurns: icon.quarterTurns, child: glyph);
    }
    return SizedBox.square(dimension: size, child: glyph);
  }

  /// Letto solo quando il colore non è passato: quasi ogni chiamante lo passa,
  /// e la dipendenza dall'[IconTheme] costerebbe una ricostruzione a ogni suo
  /// cambio. [IconTheme.of] restituisce sempre un tema risolto, colore incluso.
  static Color _currentColor(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    return iconTheme.color!.withValues(alpha: iconTheme.opacity);
  }
}

class _LinearIconPainter extends CustomPainter {
  const _LinearIconPainter({required this.icon, required this.color});

  final LinearIconData icon;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..isAntiAlias = true;
    final scale = size.shortestSide / _viewBox;

    canvas.save();
    canvas.scale(scale);
    for (final path in icon.paths) {
      canvas.drawPath(_pathCache.putIfAbsent(path, () => _build(path)), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LinearIconPainter old) =>
      old.color != color || !identical(old.icon, icon);
}

/// I glifi sono definiti su una griglia 20×20.
const double _viewBox = 20;

/// I tracciati sono costanti: convertirli in [Path] una volta sola evita di
/// ri-parsare la stessa stringa a ogni frame di una lista che scorre.
final Map<LinearIconPath, Path> _pathCache = <LinearIconPath, Path>{};

final RegExp _separator = RegExp(r'[\s,]+');

Path _build(LinearIconPath source) {
  final path = Path()
    ..fillType = source.evenOdd ? PathFillType.evenOdd : PathFillType.nonZero;
  final tokens = source.d.split(_separator)
    ..removeWhere((token) => token.isEmpty);

  var i = 0;
  var command = '';
  double next() => double.parse(tokens[i++]);

  while (i < tokens.length) {
    final token = tokens[i];
    final first = token.codeUnitAt(0);
    final isCommand =
        (first >= 0x41 && first <= 0x5A) || (first >= 0x61 && first <= 0x7A);
    if (isCommand) {
      command = token;
      i++;
    }
    switch (command) {
      case 'M':
        path.moveTo(next() + source.dx, next() + source.dy);
      case 'L':
        path.lineTo(next() + source.dx, next() + source.dy);
      case 'C':
        path.cubicTo(
          next() + source.dx,
          next() + source.dy,
          next() + source.dx,
          next() + source.dy,
          next() + source.dx,
          next() + source.dy,
        );
      case 'Z':
      case 'z':
        path.close();
      default:
        throw FormatException('Comando SVG non supportato: "$command"');
    }
  }
  return path;
}
