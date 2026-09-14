import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/app_spacing.dart';
import '../../../core/design/linear_icons.dart';
import '../../../core/design/theme_context.dart';
import '../../../core/extensions/duration_format.dart';
import '../../../core/widgets/app_field.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/linear_icon.dart';
import '../../../core/widgets/meta_chip.dart';
import '../../../core/widgets/square_icon_button.dart';
import '../../../core/widgets/surface_card.dart';
import '../../../data/entities/workout_log.dart';
import '../../../l10n/app_localizations.dart';
import '../cubit/history_cubit.dart';
import '../cubit/history_state.dart';

/// Storico allenamenti (RF-07): sessioni per data, filtro per scheda,
/// eliminazione con conferma.
class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return BlocConsumer<HistoryCubit, HistoryState>(
      listenWhen: (previous, current) =>
          previous.errorMessage != current.errorMessage,
      listener: (context, state) {
        if (state.errorMessage != null) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(state.errorMessage!)));
          context.read<HistoryCubit>().dismissError();
        }
      },
      builder: (context, state) {
        final logs = state.filteredLogs;

        return AppScaffold(
          title: l10n.historyTitle,
          header: state.isLoading || state.logs.isEmpty
              ? null
              : _PlanFilter(state: state),
          body: switch (state) {
            HistoryState(isLoading: true) => const Center(
              child: CircularProgressIndicator(),
            ),
            HistoryState(logs: []) => EmptyState(
              icon: AppIcons.calendar,
              message: l10n.historyEmpty,
            ),
            _ when logs.isEmpty => EmptyState(
              icon: AppIcons.search,
              message: l10n.historyNoResults,
            ),
            _ => ListView.separated(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                0,
                AppSpacing.xl,
                AppSpacing.tabBarClearance,
              ),
              itemCount: logs.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, index) => _HistoryTile(log: logs[index]),
            ),
          },
        );
      },
    );
  }
}

class _PlanFilter extends StatelessWidget {
  const _PlanFilter({required this.state});

  final HistoryState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final options = state.planOptions;
    if (options.length < 2) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        0,
        AppSpacing.xl,
        AppSpacing.card,
      ),
      child: DropdownButtonFormField<String?>(
        initialValue: state.planFilter,
        isExpanded: true,
        style: context.type.row,
        borderRadius: BorderRadius.circular(AppSpacing.card),
        icon: LinearIcon(
          AppIcons.chevronDown,
          size: 20,
          color: context.colors.muted,
        ),
        decoration: AppField.onBackground(
          context,
          prefixIcon: LinearIcon(
            AppIcons.lines,
            size: 20,
            color: context.colors.muted,
          ),
        ),
        items: [
          DropdownMenuItem(value: null, child: Text(l10n.historyFilterAll)),
          for (final option in options)
            DropdownMenuItem(
              value: option,
              child: Text(option, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: context.read<HistoryCubit>().filterByPlan,
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.log});

  final WorkoutLog log;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final aborted = log.status == WorkoutStatus.aborted;
    final setsCount = log.entries.fold<int>(
      0,
      (total, entry) => total + entry.sets.length,
    );

    return SurfaceCard(
      onTap: () => context.push('/history/${log.id}'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.card,
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 32,
            width: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: context.colors.fill,
            ),
            child: Center(
              child: LinearIcon(
                aborted ? AppIcons.close : AppIcons.check,
                size: 18,
                color: aborted ? context.colors.danger : context.colors.ink,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  log.planNameSnapshot,
                  style: context.type.rowStrong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.xs),
                // Data e ora in chiaro: è il dato con cui si cerca una
                // sessione nello storico.
                Text(
                  '${l10n.historySessionDate(log.startedAt)} · '
                  '${l10n.historySessionTime(log.startedAt)}',
                  style: context.type.meta,
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    MetaChip(label: log.dayLabelSnapshot),
                    MetaChip(
                      icon: AppIcons.wave,
                      label: log.duration().compact,
                    ),
                    MetaChip(label: l10n.historySetsCount(setsCount)),
                    if (aborted)
                      MetaChip(
                        label: l10n.historyStatusAborted,
                        tone: ChipTone.danger,
                      ),
                  ],
                ),
              ],
            ),
          ),
          GhostIconButton(
            icon: AppIcons.trash,
            tooltip: l10n.commonDelete,
            foreground: context.colors.muted,
            onPressed: () => _confirmDelete(context, l10n),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    AppLocalizations l10n,
  ) async {
    final cubit = context.read<HistoryCubit>();
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.historyDeleteConfirmTitle,
      message: l10n.historyDeleteConfirmBody(log.startedAt),
      confirmLabel: l10n.commonDelete,
      destructive: true,
    );
    if (confirmed) cubit.deleteLog(log.id);
  }
}
