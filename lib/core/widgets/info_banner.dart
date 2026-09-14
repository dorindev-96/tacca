import 'package:flutter/material.dart';

import '../design/app_spacing.dart';
import '../design/linear_icons.dart';
import '../design/theme_context.dart';
import 'linear_icon.dart';
import 'square_icon_button.dart';
import 'surface_card.dart';

/// Tono di un [InfoBanner]: informativo (avvisi, spiegazioni) oppure di
/// attenzione (errori, funzioni non disponibili).
enum InfoBannerTone { neutral, alert }

/// Riquadro informativo a larghezza piena: icona + testo, colore che dice
/// subito se è una spiegazione o un problema.
///
/// Esiste per non avere tre modi diversi di dare la stessa notizia
/// (avviso privacy, key mancante, errore di chiamata AI).
class InfoBanner extends StatelessWidget {
  const InfoBanner({
    required this.message,
    this.icon = AppIcons.info,
    this.tone = InfoBannerTone.neutral,
    this.onDismiss,
    super.key,
  });

  final String message;
  final LinearIconData icon;
  final InfoBannerTone tone;

  /// Quando presente, aggiunge la X per chiudere il riquadro.
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final alert = tone == InfoBannerTone.alert;
    final background = alert
        ? context.colors.dangerSurface
        : context.colors.surface;
    final foreground = alert ? context.colors.danger : context.colors.muted;

    return SurfaceCard(
      color: background,
      padding: EdgeInsets.fromLTRB(
        AppSpacing.card,
        AppSpacing.lg,
        onDismiss == null ? AppSpacing.card : AppSpacing.xs,
        AppSpacing.lg,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearIcon(icon, size: 20, color: foreground),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              message,
              style: context.type.paragraph.copyWith(
                color: alert ? context.colors.danger : context.colors.body,
              ),
            ),
          ),
          if (onDismiss != null)
            GhostIconButton(
              icon: AppIcons.close,
              foreground: foreground,
              onPressed: onDismiss,
            ),
        ],
      ),
    );
  }
}
