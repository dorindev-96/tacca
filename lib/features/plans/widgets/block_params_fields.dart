import 'package:flutter/material.dart';

import '../../../core/block_params.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/design/theme_context.dart';
import '../../../core/widgets/app_field.dart';
import '../../../data/entities/block.dart';
import '../../../l10n/app_localizations.dart';
import '../cubit/plan_editor_cubit.dart';

/// Campi specifici del tipo di blocco (§5.2 analisi funzionale): piatti e
/// nullable sull'entity, qui resi visibili solo quelli pertinenti al
/// [Block.type], nell'ordine e con le etichette di [BlockParam].
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

    if (block.type != BlockType.freeText) {
      // Tutti i tipi allo stesso modo: campi da 170 in un `Wrap`, anche dove
      // il campo è uno solo (AMRAP, For Time). Un numero di poche cifre a
      // tutta larghezza sembra un campo di testo.
      return Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.md,
        children: [
          for (final param in BlockParam.of(block.type))
            SizedBox(
              width: 170,
              child: LabeledField(
                label: param.fieldLabel(l10n),
                child: TextFormField(
                  key: ValueKey('blk-${param.fieldTag}-$instanceKey'),
                  initialValue: param.read(block)?.toString() ?? '',
                  style: context.type.row,
                  decoration: AppField.inset(context),
                  keyboardType: TextInputType.number,
                  onChanged: (v) => cubit.setBlockParam(
                    dayIndex,
                    blockIndex,
                    param,
                    int.tryParse(v),
                  ),
                ),
              ),
            ),
        ],
      );
    }

    return LabeledField(
      label: l10n.planEditorFreeTextLabel,
      child: TextFormField(
        key: ValueKey('blk-freetext-$instanceKey'),
        initialValue: block.freeTextContent ?? '',
        minLines: 3,
        maxLines: 8,
        style: context.type.fieldProse,
        decoration: AppField.inset(
          context,
          hintText: l10n.planEditorFreeTextHint,
        ),
        onChanged: (v) => cubit.setBlockFreeText(dayIndex, blockIndex, v),
      ),
    );
  }
}
