import 'package:flutter/material.dart';

import '../design/app_radius.dart';
import '../design/app_spacing.dart';
import '../design/theme_context.dart';

/// La forma dell'app: superficie piena, raggio 26, nessun bordo e nessuna
/// ombra.
///
/// Usarla ovunque serva "un pezzo di contenuto sopra il fondo" — card di un
/// blocco, riga di lista, banner, riquadro di testo. Le pagine non
/// costruiscono più [Container] con `BoxDecoration` a mano: è così che negli
/// stessi elenchi finivano raggi diversi.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(AppSpacing.card),
    this.color,
    this.radius = AppRadius.lg,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  /// Null = il colore delle card del tema. Lime per l'unico elemento in
  /// evidenza della schermata, `fill` per un riquadro *dentro* una card.
  final Color? color;

  final double radius;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
    );

    return Material(
      color: color ?? context.colors.surface,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? Padding(padding: padding, child: child)
          : InkWell(
              onTap: onTap,
              customBorder: shape,
              child: Padding(padding: padding, child: child),
            ),
    );
  }
}
