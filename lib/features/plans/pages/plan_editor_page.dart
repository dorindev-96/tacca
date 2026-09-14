import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/block_type_labels.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/design/linear_icons.dart';
import '../../../core/design/theme_context.dart';
import '../../../core/widgets/app_field.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/info_banner.dart';
import '../../../core/widgets/pill_button.dart';
import '../../../core/widgets/square_icon_button.dart';
import '../../../data/entities/block.dart';
import '../../../data/entities/workout_day.dart';
import '../../../l10n/app_localizations.dart';
import '../cubit/plan_editor_cubit.dart';
import '../cubit/plan_editor_state.dart';
import '../widgets/block_card.dart';
import '../widgets/day_tabs_bar.dart';

/// Editor manuale di una scheda (RF-02): metadati, giorni, blocchi ed
/// esercizi con riordino via drag & drop.
class PlanEditorPage extends StatelessWidget {
  const PlanEditorPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return BlocConsumer<PlanEditorCubit, PlanEditorState>(
      listenWhen: (previous, current) =>
          previous.errorMessage != current.errorMessage ||
          previous.saveSuccess != current.saveSuccess,
      listener: (context, state) {
        if (state.errorMessage != null) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(state.errorMessage!)));
          context.read<PlanEditorCubit>().dismissError();
        }
        if (state.saveSuccess) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(l10n.planEditorSaved)));
          Navigator.of(context).pop();
        }
      },
      builder: (context, state) {
        if (state.isLoading) {
          return const AppScaffold(
            leading: AppBackButton(),
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final cubit = context.read<PlanEditorCubit>();

        return PopScope(
          canPop: !state.isDirty,
          onPopInvokedWithResult: (didPop, result) async {
            if (didPop) return;
            final discard = await _confirmDiscard(context, l10n);
            if (discard && context.mounted) Navigator.of(context).pop();
          },
          child: AppScaffold(
            leading: const AppBackButton(),
            title: state.isNew
                ? l10n.planEditorNewTitle
                : l10n.planEditorEditTitle,
            actions: [
              if (state.draft.imagePaths.isNotEmpty)
                SquareIconButton(
                  icon: AppIcons.gallery,
                  tooltip: l10n.planImagesTitle,
                  onPressed: () => context.push(
                    '/plan-images',
                    extra: state.draft.imagePaths,
                  ),
                ),
            ],
            dock: PillButton(
              label: l10n.commonSave,
              icon: AppIcons.check,
              onPressed: state.isSaving ? null : cubit.save,
            ),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                0,
                AppSpacing.xl,
                AppSpacing.actionClearance,
              ),
              children: [
                if (state.isAiDraft) ...[
                  InfoBanner(
                    icon: AppIcons.cpu,
                    message: l10n.aiImportReviewNotice,
                  ),
                  const SizedBox(height: AppSpacing.card),
                ],
                LabeledField(
                  label: l10n.planEditorNameLabel,
                  child: TextFormField(
                    key: const ValueKey('plan-name'),
                    initialValue: state.draft.name,
                    style: context.type.row,
                    decoration: AppField.onBackground(
                      context,
                      hintText: l10n.planEditorNameHint,
                    ),
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: cubit.updateName,
                  ),
                ),
                const SizedBox(height: AppSpacing.card),
                LabeledField(
                  label: l10n.planEditorDescriptionLabel,
                  child: TextFormField(
                    key: const ValueKey('plan-description'),
                    initialValue: state.draft.description ?? '',
                    style: context.type.paragraph.copyWith(
                      color: context.colors.ink,
                    ),
                    decoration: AppField.onBackground(context),
                    onChanged: cubit.updateDescription,
                  ),
                ),
                const SizedBox(height: AppSpacing.card),
                LabeledField(
                  label: l10n.planEditorNotesLabel,
                  child: TextFormField(
                    key: const ValueKey('plan-notes'),
                    initialValue: state.draft.notes ?? '',
                    style: context.type.paragraph.copyWith(
                      color: context.colors.ink,
                    ),
                    decoration: AppField.onBackground(context),
                    minLines: 1,
                    maxLines: 4,
                    onChanged: cubit.updatePlanNotes,
                  ),
                ),
                // Da qui in giù si lavora sul contenuto dell'allenamento, non
                // più sui dati della scheda: lo stacco è quello fra gruppi.
                const SizedBox(height: AppSpacing.xxl),
                if (state.showDayTabs)
                  DayTabsBar(
                    days: state.draft.days.toList(),
                    selectedIndex: state.selectedDayIndex,
                    cubit: cubit,
                  )
                else
                  Align(
                    alignment: Alignment.centerLeft,
                    child: PillButton.compact(
                      label: l10n.planEditorAddDay,
                      icon: AppIcons.add,
                      tone: PillTone.outline,
                      onPressed: cubit.addDay,
                    ),
                  ),
                const SizedBox(height: AppSpacing.card),
                _DayBlocksSection(
                  key: ValueKey('day-blocks-${state.selectedDayIndex}'),
                  day: state.draft.days[state.selectedDayIndex],
                  dayIndex: state.selectedDayIndex,
                  showDayNotes: state.showDayTabs,
                  cubit: cubit,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<bool> _confirmDiscard(BuildContext context, AppLocalizations l10n) {
    return showConfirmDialog(
      context,
      title: l10n.planEditorDiscardTitle,
      message: l10n.planEditorDiscardBody,
      confirmLabel: l10n.commonDiscard,
      destructive: true,
    );
  }
}

class _DayBlocksSection extends StatelessWidget {
  const _DayBlocksSection({
    required this.day,
    required this.dayIndex,
    required this.showDayNotes,
    required this.cubit,
    super.key,
  });

  final WorkoutDay day;
  final int dayIndex;
  final bool showDayNotes;
  final PlanEditorCubit cubit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final blocks = day.blocks.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showDayNotes) ...[
          LabeledField(
            label: l10n.planEditorNotesLabel,
            child: TextFormField(
              key: ValueKey('day-notes-${identityHashCode(day)}'),
              initialValue: day.notes ?? '',
              style: context.type.paragraph.copyWith(color: context.colors.ink),
              decoration: AppField.onBackground(context),
              onChanged: (v) => cubit.updateDayNotes(dayIndex, v),
            ),
          ),
          const SizedBox(height: AppSpacing.card),
        ],
        if (blocks.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: Center(
              child: Text(l10n.dayNoBlocks, style: context.type.sectionLabel),
            ),
          )
        else
          ReorderableListView(
            key: PageStorageKey('block-list-${identityHashCode(day)}'),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorder: (oldIndex, newIndex) =>
                cubit.reorderBlocks(dayIndex, oldIndex, newIndex),
            children: [
              for (var i = 0; i < blocks.length; i++)
                BlockCard(
                  key: ValueKey('block-${identityHashCode(blocks[i])}'),
                  block: blocks[i],
                  index: i,
                  dayIndex: dayIndex,
                  cubit: cubit,
                ),
            ],
          ),
        const SizedBox(height: AppSpacing.md),
        Align(
          alignment: Alignment.centerLeft,
          child: PillButton.compact(
            label: l10n.planEditorAddBlock,
            icon: AppIcons.add,
            tone: PillTone.outline,
            onPressed: () => _pickBlockType(context, l10n, dayIndex),
          ),
        ),
      ],
    );
  }

  Future<void> _pickBlockType(
    BuildContext context,
    AppLocalizations l10n,
    int dayIndex,
  ) async {
    final type = await showAppSheet<BlockType>(
      context,
      builder: (context) => AppSheet(
        title: l10n.planEditorBlockTypeLabel,
        scrollable: true,
        children: [
          for (var i = 0; i < BlockType.values.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.sm),
            SheetOption(
              icon: AppIcons.noteAdd,
              title: blockTypeLabel(l10n, BlockType.values[i]),
              onTap: () => Navigator.of(context).pop(BlockType.values[i]),
            ),
          ],
        ],
      ),
    );
    if (type != null) cubit.addBlock(dayIndex, type);
  }
}
