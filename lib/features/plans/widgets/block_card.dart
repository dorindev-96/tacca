import 'package:flutter/material.dart';

import '../../../core/block_type_labels.dart';
import '../../../core/design/app_radius.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/design/linear_icons.dart';
import '../../../core/design/theme_context.dart';
import '../../../core/widgets/app_field.dart';
import '../../../core/widgets/linear_icon.dart';
import '../../../core/widgets/pill_button.dart';
import '../../../core/widgets/square_icon_button.dart';
import '../../../core/widgets/surface_card.dart';
import '../../../data/entities/block.dart';
import '../../../l10n/app_localizations.dart';
import '../cubit/plan_editor_cubit.dart';
import 'block_params_fields.dart';
import 'exercise_tile.dart';

/// Card espandibile per un [Block]: intestazione con riepilogo (tap per
/// espandere/comprimere) + corpo con tipo, parametri, note ed esercizi.
///
/// Il tipo non è nell'intestazione apposta: un `DropdownButtonFormField` lì
/// intercetterebbe il tap prima che possa aprire/chiudere la tile.
class BlockCard extends StatelessWidget {
  const BlockCard({
    required this.block,
    required this.index,
    required this.dayIndex,
    required this.cubit,
    super.key,
  });

  final Block block;
  final int index;
  final int dayIndex;
  final PlanEditorCubit cubit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final instanceKey = identityHashCode(block);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: SurfaceCard(
        padding: EdgeInsets.zero,
        child: ExpansionTile(
          key: PageStorageKey('block-tile-$instanceKey'),
          leading: ReorderableDragStartListener(
            index: index,
            child: GhostIconSurface(
              icon: AppIcons.lines,
              foreground: context.colors.muted,
            ),
          ),
          title: Text(
            blockTypeLabel(l10n, block.type),
            style: context.type.cardTitle,
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              _summary(l10n),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.type.paragraphSmall,
            ),
          ),
          trailing: GhostIconButton(
            icon: AppIcons.trash,
            tooltip: l10n.planEditorRemoveBlock,
            foreground: context.colors.muted,
            onPressed: () => cubit.removeBlock(dayIndex, index),
          ),
          children: [
            // Bucket isolato: gli `EditableText` annidati (campi numerici,
            // note, esercizi) usano PageStorage per il proprio scroll interno
            // e altrimenti collidono con lo stato bool di ExpansionTile
            // (flutter/flutter#36539).
            PageStorage(
              bucket: PageStorageBucket(),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.card,
                  AppSpacing.sm,
                  AppSpacing.card,
                  AppSpacing.card,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LabeledField(
                      label: l10n.planEditorBlockTypeLabel,
                      child: DropdownButtonFormField<BlockType>(
                        initialValue: block.type,
                        isExpanded: true,
                        style: context.type.row,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        icon: LinearIcon(
                          AppIcons.chevronDown,
                          size: 20,
                          color: context.colors.muted,
                        ),
                        decoration: AppField.inset(context),
                        items: [
                          for (final type in BlockType.values)
                            DropdownMenuItem(
                              value: type,
                              child: Text(blockTypeLabel(l10n, type)),
                            ),
                        ],
                        onChanged: (type) {
                          if (type != null) {
                            cubit.changeBlockType(dayIndex, index, type);
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: AppSpacing.card),
                    BlockParamsFields(
                      block: block,
                      cubit: cubit,
                      dayIndex: dayIndex,
                      blockIndex: index,
                    ),
                    if (block.type != BlockType.freeText) ...[
                      const SizedBox(height: AppSpacing.card),
                      LabeledField(
                        label: l10n.planEditorBlockNotesLabel,
                        child: TextFormField(
                          key: ValueKey('block-notes-$instanceKey'),
                          initialValue: block.notes ?? '',
                          style: context.type.paragraph.copyWith(
                            color: context.colors.ink,
                          ),
                          decoration: AppField.inset(context),
                          onChanged: (v) =>
                              cubit.updateBlockNotes(dayIndex, index, v),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.card),
                      _ExerciseList(
                        block: block,
                        dayIndex: dayIndex,
                        blockIndex: index,
                        cubit: cubit,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: PillButton.compact(
                          label: l10n.planEditorAddExercise,
                          icon: AppIcons.add,
                          tone: PillTone.outline,
                          onPressed: () => cubit.addExercise(dayIndex, index),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _summary(AppLocalizations l10n) {
    if (block.type == BlockType.freeText) {
      final content = block.freeTextContent ?? '';
      return content.trim().isEmpty ? l10n.planEditorFreeTextHint : content;
    }
    return l10n.planEditorExercisesCount(block.exercises.length);
  }
}

class _ExerciseList extends StatelessWidget {
  const _ExerciseList({
    required this.block,
    required this.dayIndex,
    required this.blockIndex,
    required this.cubit,
  });

  final Block block;
  final int dayIndex;
  final int blockIndex;
  final PlanEditorCubit cubit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final exercises = block.exercises.toList();

    if (exercises.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Text(l10n.blockNoExercises, style: context.type.sectionLabel),
      );
    }

    return ReorderableListView(
      key: PageStorageKey('exercise-list-${identityHashCode(block)}'),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      onReorder: (oldIndex, newIndex) =>
          cubit.reorderExercises(dayIndex, blockIndex, oldIndex, newIndex),
      children: [
        for (var i = 0; i < exercises.length; i++)
          ExerciseTile(
            key: ValueKey('exercise-${identityHashCode(exercises[i])}'),
            exercise: exercises[i],
            index: i,
            onNameChanged: (v) =>
                cubit.setExerciseName(dayIndex, blockIndex, i, v),
            onSetsChanged: (v) =>
                cubit.setExerciseSets(dayIndex, blockIndex, i, v),
            onRepsChanged: (v) =>
                cubit.setExerciseReps(dayIndex, blockIndex, i, v),
            onLoadChanged: (v) =>
                cubit.setExerciseLoad(dayIndex, blockIndex, i, v),
            onRestChanged: (v) =>
                cubit.setExerciseRestSeconds(dayIndex, blockIndex, i, v),
            onDurationChanged: (v) =>
                cubit.setExerciseDurationSeconds(dayIndex, blockIndex, i, v),
            onNotesChanged: (v) =>
                cubit.setExerciseNotes(dayIndex, blockIndex, i, v),
            onRemove: () => cubit.removeExercise(dayIndex, blockIndex, i),
          ),
      ],
    );
  }
}
