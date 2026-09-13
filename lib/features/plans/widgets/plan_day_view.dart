import 'package:flutter/material.dart';

import '../../../core/block_type_labels.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_radius.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_typography.dart';
import '../../../core/widgets/meta_chip.dart';
import '../../../core/widgets/surface_card.dart';
import '../../../data/entities/block.dart';
import '../../../data/entities/exercise.dart';
import '../../../data/entities/workout_day.dart';
import '../../../l10n/app_localizations.dart';

/// La scheda **in sola lettura**: giorno, blocchi, esercizi.
///
/// Vive fuori dalla pagina di dettaglio perché non è più solo sua: la stessa
/// impaginazione finisce nell'immagine da condividere ([PlanShareImage]). Due
/// copie di questi widget vorrebbero dire due schede diverse — quella che si
/// legge nell'app e quella che si manda su WhatsApp.
class PlanDaySection extends StatelessWidget {
  const PlanDaySection({required this.day, required this.showLabel, super.key});

  final WorkoutDay day;

  /// Falso sulle schede a giorno singolo: lì il giorno è implicito e
  /// l'intestazione sarebbe rumore.
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showLabel) ...[
            Text(day.label, style: AppTypography.subtitle),
            if ((day.notes ?? '').isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs + 2),
              Text(day.notes!, style: AppTypography.paragraphSmall),
            ],
            const SizedBox(height: AppSpacing.md),
          ],
          if (day.blocks.isEmpty)
            Text(l10n.dayNoBlocks, style: AppTypography.paragraphSmall)
          else
            for (final block in day.blocks)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: PlanBlockCard(block: block),
              ),
        ],
      ),
    );
  }
}

/// Card bianca di un blocco: tipo, parametri, note ed esercizi.
class PlanBlockCard extends StatelessWidget {
  const PlanBlockCard({required this.block, super.key});

  final Block block;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final exercises = block.exercises.toList();

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                blockTypeLabel(l10n, block.type),
                style: AppTypography.blockType,
              ),
              for (final param in _params(l10n)) MetaChip(label: param),
            ],
          ),
          if ((block.notes ?? '').isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(block.notes!, style: AppTypography.paragraphSmall),
          ],
          const SizedBox(height: AppSpacing.lg),
          if (block.type == BlockType.freeText)
            Text(block.freeTextContent ?? '', style: AppTypography.paragraph)
          else if (exercises.isEmpty)
            Text(l10n.blockNoExercises, style: AppTypography.paragraphSmall)
          else
            for (var i = 0; i < exercises.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.lg),
              PlanExerciseRow(exercise: exercises[i], position: i + 1),
            ],
        ],
      ),
    );
  }

  List<String> _params(AppLocalizations l10n) {
    final parts = <String>[];
    void add(String label, int? value) {
      if (value != null) parts.add('$label: $value');
    }

    switch (block.type) {
      case BlockType.standard:
      case BlockType.freeText:
        break;
      case BlockType.superset:
      case BlockType.circuit:
        add(l10n.planEditorParamRounds, block.rounds);
        add(
          l10n.planEditorParamRestBetweenRounds,
          block.restBetweenRoundsSeconds,
        );
      case BlockType.emom:
        add(l10n.planEditorParamIntervalSeconds, block.intervalSeconds);
        add(l10n.planEditorParamTotalMinutes, block.totalMinutes);
      case BlockType.amrap:
        add(l10n.planEditorParamDurationSeconds, block.durationSeconds);
      case BlockType.tabata:
        add(l10n.planEditorParamWorkSeconds, block.workSeconds);
        add(l10n.planEditorParamRestSeconds, block.restSeconds);
        add(l10n.planEditorParamRounds, block.rounds);
      case BlockType.forTime:
        add(l10n.planEditorParamTimeCapSeconds, block.timeCapSeconds);
    }
    return parts;
  }
}

/// Riga di un esercizio: numero, nome e — allineata a destra, dove l'occhio
/// la ritrova sempre — la prescrizione serie × ripetizioni.
class PlanExerciseRow extends StatelessWidget {
  const PlanExerciseRow({
    required this.exercise,
    required this.position,
    super.key,
  });

  final Exercise exercise;
  final int position;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    final volume = exercise.sets != null
        ? '${exercise.sets}×${exercise.reps ?? '?'}'
        : (exercise.reps ?? '');
    final details = <String>[
      if ((exercise.load ?? '').isNotEmpty) exercise.load!,
      if (exercise.restSeconds != null)
        l10n.planDetailExerciseRest(exercise.restSeconds!),
      if (exercise.durationSeconds != null)
        l10n.planDetailExerciseDuration(exercise.durationSeconds!),
    ];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExercisePosition(position: position),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(exercise.name, style: AppTypography.row),
              if (details.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(details.join(' · '), style: AppTypography.meta),
              ],
              if ((exercise.notes ?? '').isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  exercise.notes!,
                  style: AppTypography.paragraphSmall.copyWith(
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (volume.isNotEmpty) ...[
          const SizedBox(width: AppSpacing.sm),
          Text(volume, style: AppTypography.metaStrong.copyWith(fontSize: 14)),
        ],
      ],
    );
  }
}

/// Quadratino con il numero d'ordine dell'esercizio dentro il blocco.
class ExercisePosition extends StatelessWidget {
  const ExercisePosition({required this.position, super.key});

  final int position;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
      width: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.fill,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text('$position', style: AppTypography.chip),
    );
  }
}
