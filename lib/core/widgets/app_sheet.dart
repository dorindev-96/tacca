import 'package:flutter/material.dart';

import '../design/app_radius.dart';
import '../design/app_spacing.dart';
import '../design/linear_icons.dart';
import '../design/theme_context.dart';
import 'linear_icon.dart';
import 'square_icon_button.dart';

/// Apre un bottom sheet nella forma del restyling: bianco, raggio 24 in
/// alto, velo `rgba(25,33,38,.4)`.
///
/// Il contenuto va costruito con [AppSheet], che disegna la testata (titolo
/// Lato Black + X) sempre uguale.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool isScrollControlled = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    // Sul navigator radice, non su quello del ramo: la tab bar del
    // restyling galleggia dentro lo Stack della shell e un pannello aperto
    // sul navigator interno le finirebbe sotto.
    useRootNavigator: true,
    builder: builder,
  );
}

/// Contenuto di un bottom sheet: testata con titolo e X, poi i figli.
///
/// La X sostituisce la maniglia di trascinamento di Material: nel design il
/// pannello si chiude da un bersaglio esplicito, non da un gesto invisibile.
class AppSheet extends StatelessWidget {
  const AppSheet({
    required this.title,
    required this.children,
    this.scrollable = false,
    this.maxHeightFactor = 0.9,
    super.key,
  });

  final String title;
  final List<Widget> children;

  /// True quando i figli possono superare l'altezza dello schermo (elenchi
  /// lunghi): il corpo diventa scorrevole e la testata resta ferma.
  final bool scrollable;

  final double maxHeightFactor;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(title, style: context.type.sheetTitle)),
        const SizedBox(width: AppSpacing.md),
        SquareIconButton(
          icon: AppIcons.close,
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: media.size.height * maxHeightFactor,
      ),
      child: Padding(
        // Con la tastiera aperta il pannello sale: senza questo, i campi
        // dello sheet del log finiscono sotto i tasti.
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.xl,
              AppSpacing.xl,
              AppSpacing.xl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                const SizedBox(height: AppSpacing.card),
                if (scrollable)
                  Flexible(child: SingleChildScrollView(child: body))
                else
                  body,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Riga di scelta dentro uno sheet: riquadro grigio a raggio 26 con icona,
/// titolo ed eventuale spiegazione. La variante lime marca l'opzione
/// consigliata (una sola per pannello).
class SheetOption extends StatelessWidget {
  const SheetOption({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.highlighted = false,
    super.key,
  });

  final LinearIconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final background = highlighted ? colors.lime : colors.fill;
    // Evidenziata, la riga è una superficie lime: icona e testo non possono
    // seguire il tema, o al buio diventerebbero quasi bianchi sul lime.
    final foreground = highlighted ? colors.onLime : colors.ink;

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.card,
            vertical: AppSpacing.lg,
          ),
          child: Row(
            children: [
              LinearIcon(icon, size: 20, color: foreground),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style:
                          (highlighted
                                  ? context.type.rowStrong
                                  : context.type.row)
                              .copyWith(color: foreground),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        subtitle!,
                        style: context.type.paragraph.copyWith(
                          color: highlighted
                              ? colors.onLime.withValues(alpha: 0.72)
                              : colors.muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
