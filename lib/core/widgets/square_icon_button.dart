import 'package:flutter/material.dart';

import '../design/app_radius.dart';
import '../design/linear_icons.dart';
import '../design/theme_context.dart';
import 'linear_icon.dart';

/// Il solo *disegno* del pulsante icona quadrato: 40×40, raggio 12, contorno
/// da 1px, con 4px di margine per lato che portano l'ingombro a 48.
///
/// Esiste separato dal pulsante perché ci sono widget che il tocco lo
/// gestiscono da sé ([PopupMenuButton]) e devono comunque avere questa forma.
class SquareIconSurface extends StatelessWidget {
  const SquareIconSurface({
    required this.icon,
    this.filled = false,
    this.enabled = true,
    this.foreground,
    super.key,
  });

  final LinearIconData icon;

  /// Fondo bianco pieno invece del solo contorno: serve quando il pulsante
  /// sta già sopra una superficie bianca.
  final bool filled;

  final bool enabled;

  /// Null = l'inchiostro del tema. Un default non può leggerlo: `context` non
  /// esiste ancora quando si costruisce il widget, solo quando si disegna.
  final Color? foreground;

  static const double tapSize = 48;
  static const double boxSize = 40;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: tapSize,
      child: Center(
        child: Container(
          height: boxSize,
          width: boxSize,
          decoration: BoxDecoration(
            color: filled ? context.colors.surface : null,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: filled
                ? null
                : Border.fromBorderSide(
                    BorderSide(color: context.colors.stroke),
                  ),
          ),
          child: Center(
            child: LinearIcon(
              icon,
              color: enabled
                  ? (foreground ?? context.colors.ink)
                  : context.colors.muted,
            ),
          ),
        ),
      ),
    );
  }
}

/// Pulsante icona quadrato del restyling.
///
/// L'area tappabile è 48×48 (RNF-04: in palestra si tocca male) attorno a un
/// disegno da 40: i 4px di margine per lato sono esattamente lo spazio che
/// nel design separa due pulsanti consecutivi, quindi le testate restano
/// identiche al disegno pur avendo bersagli grandi.
class SquareIconButton extends StatelessWidget {
  const SquareIconButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.filled = false,
    this.foreground,
    super.key,
  });

  final LinearIconData icon;

  /// Null = pulsante disattivato.
  final VoidCallback? onPressed;

  final String? tooltip;
  final bool filled;

  /// Null = l'inchiostro del tema.
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    Widget button = InkResponse(
      onTap: onPressed,
      containedInkWell: true,
      highlightShape: BoxShape.rectangle,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: SquareIconSurface(
        icon: icon,
        filled: filled,
        enabled: onPressed != null,
        foreground: foreground,
      ),
    );

    if (tooltip != null) {
      button = Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}

/// Pulsante "indietro" della testata: la freccia del set Linear ruotata,
/// come nel file di design.
class AppBackButton extends StatelessWidget {
  const AppBackButton({this.onPressed, super.key});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SquareIconButton(
      icon: AppIcons.chevronLeft,
      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      onPressed: onPressed ?? () => Navigator.maybePop(context),
    );
  }
}

/// Pulsante icona tondo senza contorno, per le azioni *dentro* una riga o
/// una card (il menu "…" di una scheda, la X su una miniatura).
class GhostIconButton extends StatelessWidget {
  const GhostIconButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.foreground,
    this.size = 20,
    super.key,
  });

  final LinearIconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  /// Null = l'inchiostro del tema.
  final Color? foreground;

  final double size;

  static const double tapSize = 44;

  @override
  Widget build(BuildContext context) {
    Widget button = InkResponse(
      onTap: onPressed,
      radius: 24,
      child: GhostIconSurface(
        icon: icon,
        foreground: onPressed == null ? context.colors.muted : foreground,
        size: size,
      ),
    );
    if (tooltip != null) {
      button = Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}

/// Il disegno di [GhostIconButton], senza gestione del tocco.
class GhostIconSurface extends StatelessWidget {
  const GhostIconSurface({
    required this.icon,
    this.foreground,
    this.size = 20,
    super.key,
  });

  final LinearIconData icon;

  /// Null = l'inchiostro del tema.
  final Color? foreground;

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: GhostIconButton.tapSize,
      child: Center(
        child: LinearIcon(
          icon,
          size: size,
          color: foreground ?? context.colors.ink,
        ),
      ),
    );
  }
}
