import 'package:flutter/material.dart';

import '../../../core/design/app_radius.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/design/linear_icons.dart';
import '../../../core/design/theme_context.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/linear_icon.dart';
import '../../../data/entities/workout_day.dart';
import '../../../l10n/app_localizations.dart';
import '../cubit/plan_editor_cubit.dart';

/// Selettore orizzontale dei giorni, visibile solo per schede multi-giorno
/// (analisi funzionale §5.1: il giorno singolo è implicito e non compare).
///
/// Tap per selezionare, pressione prolungata per rinominare/rimuovere. Il
/// giorno scelto è una pillola inchiostro: la stessa relazione fra attivo e
/// non attivo della tab bar dell'app.
class DayTabsBar extends StatelessWidget {
  const DayTabsBar({
    required this.days,
    required this.selectedIndex,
    required this.cubit,
    super.key,
  });

  final List<WorkoutDay> days;
  final int selectedIndex;
  final PlanEditorCubit cubit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: days.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, i) {
          if (i == days.length) {
            return _DayChip(
              label: l10n.planEditorAddDay,
              icon: AppIcons.add,
              selected: false,
              onTap: cubit.addDay,
            );
          }
          final day = days[i];
          return _DayChip(
            label: day.label,
            selected: i == selectedIndex,
            onTap: () => cubit.selectDay(i),
            onLongPress: () => _showDayMenu(context, l10n, i, day),
          );
        },
      ),
    );
  }

  Future<void> _showDayMenu(
    BuildContext context,
    AppLocalizations l10n,
    int index,
    WorkoutDay day,
  ) async {
    final action = await showAppSheet<_DayAction>(
      context,
      builder: (context) => AppSheet(
        title: day.label,
        children: [
          SheetOption(
            icon: AppIcons.pencil,
            title: l10n.commonRename,
            onTap: () => Navigator.of(context).pop(_DayAction.rename),
          ),
          const SizedBox(height: AppSpacing.sm),
          SheetOption(
            icon: AppIcons.trash,
            title: l10n.planEditorRemoveDay,
            onTap: () => Navigator.of(context).pop(_DayAction.remove),
          ),
        ],
      ),
    );

    if (!context.mounted || action == null) return;
    switch (action) {
      case _DayAction.rename:
        await _renameDay(context, l10n, index, day.label);
      case _DayAction.remove:
        await _removeDay(context, l10n, index, day.label);
    }
  }

  Future<void> _renameDay(
    BuildContext context,
    AppLocalizations l10n,
    int index,
    String currentLabel,
  ) async {
    final newLabel = await showTextInputDialog(
      context,
      title: l10n.planEditorRenameDayTitle,
      label: l10n.planEditorDayLabel,
      initialValue: currentLabel,
    );
    if (newLabel != null && newLabel.isNotEmpty) {
      cubit.updateDayLabel(index, newLabel);
    }
  }

  Future<void> _removeDay(
    BuildContext context,
    AppLocalizations l10n,
    int index,
    String label,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.planEditorRemoveDayConfirmTitle,
      message: l10n.planEditorRemoveDayConfirmBody(label),
      confirmLabel: l10n.commonDelete,
      destructive: true,
    );
    if (confirmed) {
      cubit.removeDay(index);
    }
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.onLongPress,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final LinearIconData? icon;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final foreground = selected ? colors.onInkSurface : colors.ink;

    return Material(
      color: selected ? colors.inkSurface : colors.surface,
      borderRadius: BorderRadius.circular(AppRadius.chip),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.card),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                LinearIcon(icon!, size: 18, color: foreground),
                const SizedBox(width: AppSpacing.sm),
              ],
              Text(
                label,
                style: context.type.buttonSmall.copyWith(color: foreground),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _DayAction { rename, remove }
