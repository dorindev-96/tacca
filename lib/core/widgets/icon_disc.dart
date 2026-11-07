import 'package:flutter/widgets.dart';

import '../design/linear_icons.dart';
import 'linear_icon.dart';

/// Un glifo al centro di un disco pieno: la spunta della scheda in uso, l'esito
/// di una sessione, la sessione da riprendere, l'icona di uno stato vuoto.
///
/// I colori li sceglie chi lo usa, perché dipendono da dove sta il disco: sul
/// lime, per esempio, sia il disco sia il glifo devono restare quelli che il
/// tema scuro non capovolge.
class IconDisc extends StatelessWidget {
  const IconDisc(
    this.icon, {
    required this.size,
    required this.iconSize,
    required this.color,
    required this.iconColor,
    super.key,
  });

  final LinearIconData icon;

  /// Diametro del disco.
  final double size;
  final double iconSize;
  final Color color;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      child: Center(
        child: LinearIcon(icon, size: iconSize, color: iconColor),
      ),
    );
  }
}
