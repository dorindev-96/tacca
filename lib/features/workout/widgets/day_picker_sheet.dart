import 'package:flutter/material.dart';

import '../../../core/design/app_radius.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/design/linear_icons.dart';
import '../../../core/design/theme_context.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/linear_icon.dart';
import '../../../data/entities/workout_day.dart';
import '../../../l10n/app_localizations.dart';

/// Scelta del giorno all'avvio della sessione (RF-06).
///
/// Va mostrata solo per le schede multi-giorno: quella a giorno singolo ha un
/// giorno implicito che l'UI non deve mostrare (analisi funzionale §5.1).
Future<int?> showDayPickerSheet(
  BuildContext context, {
  required List<WorkoutDay> days,
}) {
  final l10n = AppLocalizations.of(context);

  return showAppSheet<int>(
    context,
    builder: (context) => AppSheet(
      title: l10n.workoutChooseDayTitle,
      scrollable: true,
      children: [
        for (var i = 0; i < days.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.sm),
          _DayRow(
            day: days[i],
            onTap: () => Navigator.of(context).pop(days[i].id),
          ),
        ],
      ],
    ),
  );
}

class _DayRow extends StatelessWidget {
  const _DayRow({required this.day, required this.onTap});

  final WorkoutDay day;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final notes = day.notes ?? '';

    return Material(
      color: context.colors.fill,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.card,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              _DayInitial(label: day.label),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(day.label, style: context.type.row),
                    if (notes.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        notes,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.type.paragraphSmall,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              LinearIcon(
                AppIcons.chevronRight,
                size: 20,
                color: context.colors.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sigla del giorno ("Giorno A" → "A"): dà a ogni riga un aggancio visivo
/// che si riconosce prima di leggere l'etichetta.
class _DayInitial extends StatelessWidget {
  const _DayInitial({required this.label});

  final String label;

  String get _initial {
    final words = label.trim().split(RegExp(r'\s+'));
    final last = words.isEmpty ? '' : words.last;
    if (last.isEmpty) return '?';
    return last.substring(0, 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      width: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: context.colors.surface,
      ),
      child: Text(_initial, style: context.type.rowStrong),
    );
  }
}
