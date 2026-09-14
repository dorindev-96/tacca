import 'package:flutter/material.dart';

import '../../../core/design/app_spacing.dart';
import '../../../core/design/theme_context.dart';
import '../../../core/widgets/app_field.dart';
import '../../../data/entities/block.dart';
import '../../../l10n/app_localizations.dart';
import '../cubit/plan_editor_cubit.dart';

/// Campi specifici del tipo di blocco (§5.2 analisi funzionale): piatti e
/// nullable sull'entity, qui resi visibili solo quelli pertinenti al
/// [Block.type].
class BlockParamsFields extends StatelessWidget {
  const BlockParamsFields({
    required this.block,
    required this.cubit,
    required this.dayIndex,
    required this.blockIndex,
    super.key,
  });

  final Block block;
  final PlanEditorCubit cubit;
  final int dayIndex;
  final int blockIndex;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final instanceKey = identityHashCode(block);

    Widget numberField({
      required String tag,
      required String label,
      required int? value,
      required ValueChanged<int?> onChanged,
    }) {
      return SizedBox(
        width: 170,
        child: LabeledField(
          label: label,
          child: TextFormField(
            key: ValueKey('blk-$tag-$instanceKey'),
            initialValue: value?.toString() ?? '',
            style: context.type.row,
            decoration: AppField.inset(context),
            keyboardType: TextInputType.number,
            onChanged: (v) => onChanged(int.tryParse(v)),
          ),
        ),
      );
    }

    Widget wrap(List<Widget> fields) => Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.md,
      children: fields,
    );

    switch (block.type) {
      case BlockType.standard:
        return const SizedBox.shrink();
      case BlockType.superset:
      case BlockType.circuit:
        return wrap([
          numberField(
            tag: 'rounds',
            label: l10n.planEditorParamRounds,
            value: block.rounds,
            onChanged: (v) => cubit.setBlockRounds(dayIndex, blockIndex, v),
          ),
          numberField(
            tag: 'restRounds',
            label: l10n.planEditorParamRestBetweenRounds,
            value: block.restBetweenRoundsSeconds,
            onChanged: (v) =>
                cubit.setBlockRestBetweenRoundsSeconds(dayIndex, blockIndex, v),
          ),
        ]);
      case BlockType.emom:
        return wrap([
          numberField(
            tag: 'interval',
            label: l10n.planEditorParamIntervalSeconds,
            value: block.intervalSeconds,
            onChanged: (v) =>
                cubit.setBlockIntervalSeconds(dayIndex, blockIndex, v),
          ),
          numberField(
            tag: 'totalMin',
            label: l10n.planEditorParamTotalMinutes,
            value: block.totalMinutes,
            onChanged: (v) =>
                cubit.setBlockTotalMinutes(dayIndex, blockIndex, v),
          ),
        ]);
      case BlockType.amrap:
        return numberField(
          tag: 'duration',
          label: l10n.planEditorParamDurationSeconds,
          value: block.durationSeconds,
          onChanged: (v) =>
              cubit.setBlockDurationSeconds(dayIndex, blockIndex, v),
        );
      case BlockType.tabata:
        return wrap([
          numberField(
            tag: 'work',
            label: l10n.planEditorParamWorkSeconds,
            value: block.workSeconds,
            onChanged: (v) =>
                cubit.setBlockWorkSeconds(dayIndex, blockIndex, v),
          ),
          numberField(
            tag: 'rest',
            label: l10n.planEditorParamRestSeconds,
            value: block.restSeconds,
            onChanged: (v) =>
                cubit.setBlockRestSeconds(dayIndex, blockIndex, v),
          ),
          numberField(
            tag: 'rounds',
            label: l10n.planEditorParamRounds,
            value: block.rounds,
            onChanged: (v) => cubit.setBlockRounds(dayIndex, blockIndex, v),
          ),
        ]);
      case BlockType.forTime:
        return numberField(
          tag: 'timeCap',
          label: l10n.planEditorParamTimeCapSeconds,
          value: block.timeCapSeconds,
          onChanged: (v) =>
              cubit.setBlockTimeCapSeconds(dayIndex, blockIndex, v),
        );
      case BlockType.freeText:
        return LabeledField(
          label: l10n.planEditorFreeTextLabel,
          child: TextFormField(
            key: ValueKey('blk-freetext-$instanceKey'),
            initialValue: block.freeTextContent ?? '',
            minLines: 3,
            maxLines: 8,
            style: context.type.paragraph.copyWith(color: context.colors.ink),
            decoration: AppField.inset(
              context,
              hintText: l10n.planEditorFreeTextHint,
            ),
            onChanged: (v) => cubit.setBlockFreeText(dayIndex, blockIndex, v),
          ),
        );
    }
  }
}
