import 'package:flutter/material.dart';

import '../design/app_spacing.dart';
import '../design/linear_icons.dart';
import '../design/theme_context.dart';
import 'linear_icon.dart';
import 'square_icon_button.dart';

/// Voce di un menu contestuale: riga alta 48, testo Lato 16, inset 20.
///
/// Nel design le voci sono **solo testo**: l'icona compare unicamente su
/// "Elimina", ed è lì che serve — è l'unica voce da cui non si torna
/// indietro.
///
/// Il contenuto passa da un [Builder] perché questa è una funzione, non un
/// widget: il contesto in cui leggere i colori è quello in cui la voce viene
/// *disegnata* (l'overlay del menu, che porta con sé il tema di chi l'ha
/// aperto), non quello di chi la costruisce. Tenerla una funzione significa
/// che i chiamanti non cambiano.
PopupMenuItem<T> appMenuItem<T>({
  required T value,
  required String label,
  LinearIconData? icon,
  bool destructive = false,
  bool enabled = true,
}) {
  return PopupMenuItem<T>(
    value: value,
    enabled: enabled,
    height: 48,
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.card),
    child: Builder(
      builder: (context) {
        final color = destructive ? context.colors.danger : context.colors.ink;

        return Row(
          children: [
            if (icon != null) ...[
              LinearIcon(icon, size: 20, color: color),
              const SizedBox(width: AppSpacing.sm),
            ],
            Flexible(
              child: Text(
                label,
                style: context.type.row.copyWith(color: color),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
      },
    ),
  );
}

/// Voce di menu con spunta (il "Recupero automatico dopo la spunta" della
/// sessione): quadratino lime quando è attiva, contorno vuoto quando non lo è.
PopupMenuItem<T> appMenuCheckItem<T>({
  required T value,
  required String label,
  required bool checked,
}) {
  return PopupMenuItem<T>(
    value: value,
    height: 56,
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.card),
    child: Builder(
      builder: (context) => Row(
        children: [
          Container(
            height: 24,
            width: 24,
            decoration: BoxDecoration(
              color: checked ? context.colors.lime : null,
              borderRadius: BorderRadius.circular(AppSpacing.sm),
              border: checked
                  ? null
                  : Border.fromBorderSide(
                      BorderSide(color: context.colors.stroke),
                    ),
            ),
            // La spunta sta sopra il lime: inchiostro che non si capovolge.
            child: checked
                ? Center(
                    child: LinearIcon(
                      AppIcons.check,
                      size: 16,
                      color: context.colors.onLime,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(label, style: context.type.row)),
        ],
      ),
    ),
  );
}

/// Forma del pulsante che apre un [AppMenuButton].
enum MenuButtonShape {
  /// Quadrato con contorno: nelle testate.
  square,

  /// Tondo senza contorno: dentro una riga o una card.
  ghost,
}

/// Pulsante "…" che apre un menu contestuale nella forma del restyling
/// (bianco, raggio 26, ombra flottante — tutto dal tema).
class AppMenuButton<T> extends StatelessWidget {
  const AppMenuButton({
    required this.itemBuilder,
    required this.onSelected,
    this.shape = MenuButtonShape.square,
    this.foreground,
    this.tooltip,
    super.key,
  });

  final PopupMenuItemBuilder<T> itemBuilder;
  final PopupMenuItemSelected<T> onSelected;
  final MenuButtonShape shape;

  /// Null = l'inchiostro del tema.
  final Color? foreground;

  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<T>(
      onSelected: onSelected,
      itemBuilder: itemBuilder,
      tooltip: tooltip ?? MaterialLocalizations.of(context).showMenuTooltip,
      padding: EdgeInsets.zero,
      position: PopupMenuPosition.under,
      child: switch (shape) {
        MenuButtonShape.square => SquareIconSurface(
          icon: AppIcons.dots,
          foreground: foreground,
        ),
        MenuButtonShape.ghost => GhostIconSurface(
          icon: AppIcons.dots,
          foreground: foreground,
        ),
      },
    );
  }
}
