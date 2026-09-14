import 'package:flutter/material.dart';

import '../../../core/design/app_radius.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/design/theme_context.dart';
import '../../../core/extensions/duration_format.dart';
import '../../../core/extensions/log_set_format.dart';
import '../../../core/widgets/app_field.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/pill_button.dart';
import '../../../l10n/app_localizations.dart';
import '../bloc/session_item.dart';

/// Conferma di chiusura della sessione con le note inserite.
class SessionSummaryConfirmed {
  const SessionSummaryConfirmed(this.notes);

  final String? notes;
}

/// Riepilogo di fine sessione (RF-06): durata, esercizi completati, carichi e
/// note libere prima di consegnare il log allo storico.
Future<SessionSummaryConfirmed?> showSessionSummarySheet(
  BuildContext context, {
  required Duration elapsed,
  required int completedExercises,
  required int totalExercises,
  required int loggedSets,
  required List<SessionItem> items,
  String? initialNotes,
}) {
  return showAppSheet<SessionSummaryConfirmed>(
    context,
    builder: (context) => _SessionSummarySheet(
      elapsed: elapsed,
      completedExercises: completedExercises,
      totalExercises: totalExercises,
      loggedSets: loggedSets,
      items: items,
      initialNotes: initialNotes,
    ),
  );
}

class _SessionSummarySheet extends StatefulWidget {
  const _SessionSummarySheet({
    required this.elapsed,
    required this.completedExercises,
    required this.totalExercises,
    required this.loggedSets,
    required this.items,
    required this.initialNotes,
  });

  final Duration elapsed;
  final int completedExercises;
  final int totalExercises;
  final int loggedSets;
  final List<SessionItem> items;
  final String? initialNotes;

  @override
  State<_SessionSummarySheet> createState() => _SessionSummarySheetState();
}

class _SessionSummarySheetState extends State<_SessionSummarySheet> {
  late final TextEditingController _notes = TextEditingController(
    text: widget.initialNotes ?? '',
  );

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final performed = widget.items
        .where((item) => item.entry.sets.isNotEmpty)
        .toList();

    return AppSheet(
      title: l10n.workoutSummaryTitle,
      scrollable: true,
      children: [
        // I tre numeri che riassumono la sessione, alla stessa altezza: si
        // leggono in un colpo d'occhio.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Stat(
                label: l10n.workoutSummaryDuration,
                value: widget.elapsed.compact,
              ),
              const SizedBox(width: AppSpacing.sm),
              _Stat(
                label: l10n.workoutSummaryExercises,
                value: '${widget.completedExercises}/${widget.totalExercises}',
              ),
              const SizedBox(width: AppSpacing.sm),
              _Stat(
                label: l10n.workoutSummarySets,
                value: '${widget.loggedSets}',
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.card),
        for (final item in performed)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(item.name, style: context.type.row)),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    item.completedSets.map((set) => set.summary).join(' · '),
                    textAlign: TextAlign.end,
                    style: context.type.meta,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        FieldLabel(l10n.workoutSummaryNotesLabel),
        TextField(
          key: const ValueKey('session-notes'),
          controller: _notes,
          minLines: 1,
          maxLines: 3,
          style: context.type.paragraph.copyWith(color: context.colors.ink),
          decoration: AppField.inset(context),
        ),
        const SizedBox(height: AppSpacing.card),
        Row(
          children: [
            PillButton(
              label: l10n.commonContinue,
              tone: PillTone.outline,
              expand: false,
              onPressed: () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: PillButton(
                label: l10n.workoutSummaryConfirm,
                onPressed: () => Navigator.of(context).pop(
                  SessionSummaryConfirmed(
                    _notes.text.trim().isEmpty ? null : _notes.text.trim(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Un numero del riepilogo: valore grande sopra, etichetta sotto.
class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.lg,
        ),
        decoration: BoxDecoration(
          color: context.colors.fill,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Column(
          children: [
            Text(value, style: context.type.numericField),
            const SizedBox(height: AppSpacing.xs),
            Text(
              label,
              textAlign: TextAlign.center,
              style: context.type.caption,
            ),
          ],
        ),
      ),
    );
  }
}
