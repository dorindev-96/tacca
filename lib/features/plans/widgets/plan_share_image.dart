import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_typography.dart';
import '../../../core/design/linear_icons.dart';
import '../../../core/widgets/meta_chip.dart';
import '../../../core/widgets/surface_card.dart';
import '../../../data/entities/workout_plan.dart';
import '../../../l10n/app_localizations.dart';
import 'plan_day_view.dart';

/// La scheda intera impaginata come **una sola immagine**, da mandare in chat.
///
/// Non è una schermata: viene disegnata fuori dall'albero dell'app da
/// `WidgetImageRenderer`, che le dà una larghezza fissa ([logicalWidth]) e la
/// lascia crescere in altezza quanto serve. Da qui tre conseguenze:
///
/// * si porta dietro il proprio contesto — [Directionality], [MediaQuery],
///   [Localizations] e [Theme] — perché sopra di lei non c'è nessun
///   `MaterialApp`. Il [MediaQuery] è volutamente quello di default: il
///   fattore di ingrandimento del testo del telefono di chi condivide non
///   deve sfondare un'impaginazione a larghezza fissa;
/// * niente `ListView` e niente `Expanded`: in altezza non c'è un viewport da
///   riempire, c'è una colonna che si misura da sé;
/// * niente lime. Nell'app l'accento dice "questo, adesso" (la scheda in uso,
///   l'esercizio corrente); dentro un'immagine spedita a qualcun altro non
///   direbbe niente, quindi le chip di stato ("In uso", "Archiviata") qui non
///   compaiono: restano il numero di giorni e il contenuto della scheda.
class PlanShareImage extends StatelessWidget {
  const PlanShareImage({required this.plan, required this.locale, super.key});

  final WorkoutPlan plan;

  /// La lingua con cui impaginare: fuori dall'albero dell'app non c'è nessuno
  /// da cui ereditarla, quindi la passa il chiamante
  /// (`Localizations.localeOf`).
  final Locale locale;

  /// Larghezza logica dell'immagine. Vicina a quella di un telefono, così le
  /// righe vanno a capo dove l'utente le ha viste andare a capo nell'app; il
  /// numero di pixel veri lo decide il `pixelRatio` del rendering.
  static const double logicalWidth = 420;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(),
        child: Localizations(
          locale: locale,
          delegates: AppLocalizations.localizationsDelegates,
          child: Theme(
            data: AppTheme.theme,
            child: Builder(builder: _buildSheet),
          ),
        ),
      ),
    );
  }

  Widget _buildSheet(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final showDayLabels = plan.days.length > 1;

    return ColoredBox(
      color: AppColors.background,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(plan.name, style: AppTypography.screenTitle),
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerLeft,
              child: MetaChip(
                icon: AppIcons.calendar,
                label: l10n.plansDaysCount(plan.days.length),
                tone: ChipTone.onBackground,
                small: false,
              ),
            ),
            if ((plan.description ?? '').isNotEmpty)
              _TextSection(
                label: l10n.planDetailDescriptionLabel,
                text: plan.description!,
              ),
            if ((plan.notes ?? '').isNotEmpty)
              _TextSection(label: l10n.planDetailNotesLabel, text: plan.notes!),
            for (final day in plan.days)
              PlanDaySection(day: day, showLabel: showDayLabels),
          ],
        ),
      ),
    );
  }
}

/// Descrizione o note: label grigia + riquadro bianco, come nel dettaglio.
///
/// Non usa `Section` perché quello imposta `crossAxisAlignment.stretch` su una
/// colonna che qui è già stirata, e soprattutto perché la label qui deve
/// restare attaccata al testo anche senza il resto della pagina intorno.
class _TextSection extends StatelessWidget {
  const _TextSection({required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: AppTypography.sectionLabel),
          const SizedBox(height: AppSpacing.md),
          SurfaceCard(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.card,
              vertical: AppSpacing.lg,
            ),
            child: Text(text, style: AppTypography.paragraph),
          ),
        ],
      ),
    );
  }
}
