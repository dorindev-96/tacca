import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/design/app_spacing.dart';
import '../../../core/design/linear_icons.dart';
import '../../../core/design/theme_context.dart';
import '../../../core/extensions/duration_format.dart';
import '../../../core/extensions/log_set_format.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/meta_chip.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/square_icon_button.dart';
import '../../../core/widgets/surface_card.dart';
import '../../../data/entities/log_entry.dart';
import '../../../data/entities/workout_log.dart';
import '../../../l10n/app_localizations.dart';
import '../cubit/history_detail_cubit.dart';

/// Dettaglio di una sessione (RF-07): esercizi, serie, carichi e note.
///
/// Legge solo dagli snapshot del log, quindi resta leggibile anche se la
/// scheda di origine è stata modificata o eliminata (§4).
class HistoryDetailPage extends StatelessWidget {
  const HistoryDetailPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return BlocBuilder<HistoryDetailCubit, WorkoutLog?>(
      builder: (context, log) {
        if (log == null) {
          return AppScaffold(
            leading: const AppBackButton(),
            body: EmptyState(
              icon: AppIcons.search,
              message: l10n.workoutSessionNotFound,
            ),
          );
        }

        final aborted = log.status == WorkoutStatus.aborted;
        final entries = _sortedEntries(log);

        return AppScaffold(
          leading: const AppBackButton(),
          actions: [
            SquareIconButton(
              icon: AppIcons.trash,
              tooltip: l10n.commonDelete,
              foreground: context.colors.danger,
              onPressed: () => _confirmDelete(context, l10n, log),
            ),
          ],
          body: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              0,
              AppSpacing.xl,
              AppSpacing.xxl,
            ),
            children: [
              Text(log.planNameSnapshot, style: context.type.screenTitle),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '${l10n.historySessionDate(log.startedAt)} '
                '${l10n.historySessionTime(log.startedAt)}',
                style: context.type.sectionLabel,
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  MetaChip(
                    icon: AppIcons.calendar,
                    label: log.dayLabelSnapshot,
                    tone: ChipTone.onBackground,
                    small: false,
                  ),
                  MetaChip(
                    icon: AppIcons.wave,
                    label: log.duration().compact,
                    tone: ChipTone.onBackground,
                    small: false,
                  ),
                  MetaChip(
                    label: _statusLabel(l10n, log.status),
                    tone: aborted ? ChipTone.danger : ChipTone.accent,
                    small: false,
                  ),
                ],
              ),
              if ((log.notes ?? '').isNotEmpty)
                Section(
                  label: l10n.historySessionNotesLabel,
                  child: SurfaceCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.card,
                      vertical: AppSpacing.lg,
                    ),
                    child: Text(log.notes!, style: context.type.paragraph),
                  ),
                ),
              const SizedBox(height: AppSpacing.xl),
              for (final entry in entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _EntryCard(entry: entry),
                ),
            ],
          ),
        );
      },
    );
  }

  List<LogEntry> _sortedEntries(WorkoutLog log) =>
      log.entries.toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  String _statusLabel(AppLocalizations l10n, WorkoutStatus status) {
    switch (status) {
      case WorkoutStatus.completed:
        return l10n.historyStatusCompleted;
      case WorkoutStatus.aborted:
        return l10n.historyStatusAborted;
      case WorkoutStatus.inProgress:
        return l10n.historyStatusInProgress;
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    AppLocalizations l10n,
    WorkoutLog log,
  ) async {
    final cubit = context.read<HistoryDetailCubit>();
    final navigator = Navigator.of(context);
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.historyDeleteConfirmTitle,
      message: l10n.historyDeleteConfirmBody(log.startedAt),
      confirmLabel: l10n.commonDelete,
      destructive: true,
    );
    if (confirmed) {
      cubit.delete();
      navigator.pop();
    }
  }
}

/// Un esercizio della sessione: nome e serie registrate, una per riga, con i
/// numeri incolonnati (si confrontano a colpo d'occhio).
class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry});

  final LogEntry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sets = entry.sets.toList()
      ..sort((a, b) => a.setNumber.compareTo(b.setNumber));

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(entry.exerciseNameSnapshot, style: context.type.cardTitle),
          const SizedBox(height: AppSpacing.md),
          if (sets.isEmpty)
            Text(l10n.historyExerciseNotDone, style: context.type.meta)
          else
            for (final set in sets)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        SizedBox(
                          width: 84,
                          child: Text(
                            l10n.workoutSetLabel(set.setNumber),
                            style: context.type.row.copyWith(
                              color: context.colors.muted,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(set.summary, style: context.type.numeric),
                        ),
                      ],
                    ),
                    if ((set.notes ?? '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(
                          left: 84,
                          top: AppSpacing.xs,
                        ),
                        child: Text(
                          set.notes!,
                          style: context.type.paragraphSmall.copyWith(
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
