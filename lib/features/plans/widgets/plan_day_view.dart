import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/block_type_labels.dart';
import '../../../core/design/app_radius.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/design/theme_context.dart';
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
///
/// Nel dettaglio il giorno si disegna intero; nell'immagine può doversi
/// spezzare fra due pagine, e allora se ne disegna solo una parte ([part]).
/// È lo stesso widget in entrambi i casi, così una scheda divisa in pagine
/// resta identica a quella che si legge.
class PlanDaySection extends StatelessWidget {
  const PlanDaySection({
    required this.day,
    required this.showLabel,
    this.part,
    super.key,
  });

  final WorkoutDay day;

  /// Falso sulle schede a giorno singolo: lì il giorno è implicito e
  /// l'intestazione sarebbe rumore.
  final bool showLabel;

  /// La parte del giorno da disegnare; null = tutto il giorno.
  final PlanDayPart? part;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final blocks = day.blocks.toList();
    final part = this.part;
    final opensDay = part?.opensDay ?? true;

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showLabel) ...[
            Text(day.label, style: context.type.subtitle),
            if (opensDay && (day.notes ?? '').isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs + 2),
              Text(day.notes!, style: context.type.paragraphSmall),
            ],
            const SizedBox(height: AppSpacing.md),
          ],
          if (blocks.isEmpty)
            Text(l10n.dayNoBlocks, style: context.type.paragraphSmall)
          else if (part == null)
            for (final block in blocks)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: PlanBlockCard(block: block),
              )
          else
            for (final piece in part.blocks)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: PlanBlockCard(
                  block: blocks[piece.block],
                  rows: (start: piece.start, end: piece.end),
                ),
              ),
        ],
      ),
    );
  }
}

/// La parte di un giorno che sta in una pagina dell'immagine condivisa.
///
/// Una pagina che riprende un giorno a metà ne ripete l'etichetta, perché chi
/// la guarda da sola in una chat deve sapere di che giorno si tratta, ma non
/// le note: quelle le ha già lette in cima al giorno, sulla pagina prima.
class PlanDayPart {
  const PlanDayPart({required this.opensDay, required this.blocks});

  /// True se la parte comincia dal giorno stesso: etichetta *e* note.
  final bool opensDay;

  /// I blocchi della parte, ognuno con le righe che ci stanno.
  final List<PlanBlockRows> blocks;
}

/// Un blocco, o il pezzo di un blocco, dentro una [PlanDayPart].
class PlanBlockRows {
  const PlanBlockRows({
    required this.block,
    required this.start,
    required this.end,
  });

  /// Indice del blocco nel giorno.
  final int block;

  /// Prima riga inclusa e ultima esclusa (vedi [PlanBlockCard.rowCountOf]).
  final int start;
  final int end;
}

/// Card bianca di un blocco: tipo, parametri, note ed esercizi.
///
/// Quando il blocco non sta in una pagina dell'immagine condivisa se ne
/// disegnano solo alcune righe ([rows]). Il pezzo che continua ripete tipo e
/// parametri, perché una card senza intestazione in cima a una pagina non
/// direbbe che cosa si sta leggendo, ma non le note; la numerazione degli
/// esercizi prosegue da dove si era fermata.
class PlanBlockCard extends StatelessWidget {
  const PlanBlockCard({required this.block, this.rows, super.key});

  final Block block;

  /// Le righe da disegnare, dalla `start` inclusa alla `end` esclusa (vedi
  /// [rowCountOf]); null = tutto il blocco.
  final ({int start, int end})? rows;

  /// In quante righe si può spezzare [block] fra due pagine: un esercizio per
  /// riga, oppure le righe del testo libero, che dopo un import AI non
  /// riuscito può contenere una scheda intera. Un blocco vuoto è una riga
  /// sola: quella che dice che è vuoto.
  static int rowCountOf(Block block) => block.type == BlockType.freeText
      ? _freeTextLines(block).length
      : math.max(1, block.exercises.length);

  static List<String> _freeTextLines(Block block) =>
      (block.freeTextContent ?? '').split('\n');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final exercises = block.exercises.toList();
    final rows = this.rows;
    final start = rows?.start ?? 0;
    final end = rows?.end ?? rowCountOf(block);

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
                style: context.type.blockType,
              ),
              for (final param in _params(l10n)) MetaChip(label: param),
            ],
          ),
          if (start == 0 && (block.notes ?? '').isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(block.notes!, style: context.type.paragraphSmall),
          ],
          const SizedBox(height: AppSpacing.lg),
          if (block.type == BlockType.freeText)
            Text(
              rows == null
                  ? (block.freeTextContent ?? '')
                  : _freeTextLines(block).sublist(start, end).join('\n'),
              style: context.type.paragraph,
            )
          else if (exercises.isEmpty)
            Text(l10n.blockNoExercises, style: context.type.paragraphSmall)
          else
            for (var i = start; i < end; i++) ...[
              if (i > start) const SizedBox(height: AppSpacing.lg),
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
              Text(exercise.name, style: context.type.row),
              if (details.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(details.join(' · '), style: context.type.meta),
              ],
              if ((exercise.notes ?? '').isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  exercise.notes!,
                  style: context.type.paragraphSmall.copyWith(
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (volume.isNotEmpty) ...[
          const SizedBox(width: AppSpacing.sm),
          Text(volume, style: context.type.metaStrong.copyWith(fontSize: 14)),
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
        color: context.colors.fill,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text('$position', style: context.type.chip),
    );
  }
}
