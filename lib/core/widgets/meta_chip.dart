import 'package:flutter/material.dart';

import '../design/app_radius.dart';
import '../design/app_spacing.dart';
import '../design/linear_icons.dart';
import '../design/theme_context.dart';
import 'linear_icon.dart';

/// Tono di una [MetaChip].
enum ChipTone {
  /// Incavo neutro: il dato secondario dentro una card.
  neutral,

  /// Colore delle card: lo stesso dato quando la chip sta sul fondo pagina.
  onBackground,

  /// Lime: l'unico dato in evidenza della schermata ("In uso").
  accent,

  /// Inchiostro trasparente: la chip sopra una card lime.
  onAccent,

  /// Rosa: sessione interrotta.
  danger,
}

/// Etichetta compatta per un dato secondario (durata, numero di serie, tipo
/// di blocco, parametri).
///
/// È volutamente *non* tappabile: sostituisce le stringhe concatenate con
/// " · ", che a colpo d'occhio sono un blocco di testo unico e illeggibile.
class MetaChip extends StatelessWidget {
  const MetaChip({
    required this.label,
    this.icon,
    this.tone = ChipTone.neutral,
    this.small = true,
    super.key,
  });

  final String label;
  final LinearIconData? icon;
  final ChipTone tone;

  /// Chip piccola (26, testo 12): quella che sta *dentro* una card. False =
  /// chip grande (32, testo 13) usata sotto il titolo di una schermata.
  final bool small;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    // I due toni che stanno *sopra* il lime prendono l'inchiostro che non si
    // capovolge: `ink` qui diventerebbe quasi bianco su lime.
    final (background, foreground, strong) = switch (tone) {
      ChipTone.neutral => (colors.fill, colors.muted, false),
      ChipTone.onBackground => (colors.surface, colors.ink, false),
      ChipTone.accent => (colors.lime, colors.onLime, true),
      ChipTone.onAccent => (
        colors.onLime.withValues(alpha: 0.16),
        colors.onLime,
        true,
      ),
      ChipTone.danger => (colors.dangerSurface, colors.danger, true),
    };

    final type = context.type;
    final style =
        (small
                ? (strong ? type.chipStrong : type.chip)
                : (strong ? type.metaStrong : type.meta))
            .copyWith(color: foreground);

    return Container(
      height: small ? 26 : 32,
      padding: EdgeInsets.symmetric(
        horizontal: small ? AppSpacing.sm + 2 : AppSpacing.lg - 2,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            LinearIcon(icon!, size: small ? 14 : 16, color: foreground),
            const SizedBox(width: AppSpacing.sm),
          ],
          Text(label, style: style),
        ],
      ),
    );
  }
}
