import 'package:flutter/material.dart';

import '../../../core/design/app_radius.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/design/linear_icons.dart';
import '../../../core/design/theme_context.dart';
import '../../../core/widgets/app_field.dart';
import '../../../core/widgets/square_icon_button.dart';
import '../../../data/entities/exercise.dart';
import '../../../l10n/app_localizations.dart';

/// Riga di editing per un [Exercise]: tutti i campi tranne il nome sono
/// opzionali (analisi funzionale §5.1).
///
/// I campi di un esercizio stanno in un riquadro grigio dentro la card
/// bianca del blocco: in un blocco con sei esercizi, senza contenitore non si
/// capisce dove finisce uno e inizia il successivo.
class ExerciseTile extends StatelessWidget {
  const ExerciseTile({
    required this.exercise,
    required this.index,
    required this.onNameChanged,
    required this.onSetsChanged,
    required this.onRepsChanged,
    required this.onLoadChanged,
    required this.onRestChanged,
    required this.onDurationChanged,
    required this.onNotesChanged,
    required this.onRemove,
    super.key,
  });

  final Exercise exercise;
  final int index;
  final ValueChanged<String> onNameChanged;
  final ValueChanged<int?> onSetsChanged;
  final ValueChanged<String?> onRepsChanged;
  final ValueChanged<String?> onLoadChanged;
  final ValueChanged<int?> onRestChanged;
  final ValueChanged<int?> onDurationChanged;
  final ValueChanged<String?> onNotesChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final instanceKey = identityHashCode(exercise);

    // Dentro il riquadro grigio i campi tornano bianchi: è il contrasto che
    // li fa leggere come campi e non come testo.
    Widget numberField({
      required String tag,
      required String label,
      required int? value,
      required ValueChanged<int?> onChanged,
      double width = 128,
    }) {
      return SizedBox(
        width: width,
        child: LabeledField(
          label: label,
          child: TextFormField(
            key: ValueKey('ex-$tag-$instanceKey'),
            initialValue: value?.toString() ?? '',
            style: context.type.row,
            decoration: AppField.onBackground(context),
            keyboardType: TextInputType.number,
            onChanged: (v) => onChanged(int.tryParse(v)),
          ),
        ),
      );
    }

    Widget textField({
      required String tag,
      required String label,
      required String value,
      required ValueChanged<String> onChanged,
      double width = 168,
    }) {
      return SizedBox(
        width: width,
        child: LabeledField(
          label: label,
          child: TextFormField(
            key: ValueKey('ex-$tag-$instanceKey'),
            initialValue: value,
            style: context.type.row,
            decoration: AppField.onBackground(context),
            onChanged: onChanged,
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: context.colors.fill,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: GhostIconSurface(
                  icon: AppIcons.lines,
                  foreground: context.colors.muted,
                ),
              ),
              Expanded(
                child: LabeledField(
                  label: l10n.planEditorExerciseNameLabel,
                  child: TextFormField(
                    key: ValueKey('ex-name-$instanceKey'),
                    initialValue: exercise.name,
                    style: context.type.row,
                    decoration: AppField.onBackground(context),
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: onNameChanged,
                  ),
                ),
              ),
              GhostIconButton(
                icon: AppIcons.trash,
                tooltip: l10n.planEditorRemoveExercise,
                foreground: context.colors.muted,
                onPressed: onRemove,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.xs),
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.md,
              children: [
                numberField(
                  tag: 'sets',
                  label: l10n.planEditorExerciseSetsLabel,
                  value: exercise.sets,
                  onChanged: onSetsChanged,
                ),
                textField(
                  tag: 'reps',
                  label: l10n.planEditorExerciseRepsLabel,
                  value: exercise.reps ?? '',
                  onChanged: onRepsChanged,
                  width: 128,
                ),
                textField(
                  tag: 'load',
                  label: l10n.planEditorExerciseLoadLabel,
                  value: exercise.load ?? '',
                  onChanged: onLoadChanged,
                ),
                numberField(
                  tag: 'rest',
                  label: l10n.planEditorExerciseRestLabel,
                  value: exercise.restSeconds,
                  onChanged: onRestChanged,
                ),
                numberField(
                  tag: 'duration',
                  label: l10n.planEditorExerciseDurationLabel,
                  value: exercise.durationSeconds,
                  onChanged: onDurationChanged,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.xs),
            child: LabeledField(
              label: l10n.planEditorExerciseNotesLabel,
              child: TextFormField(
                key: ValueKey('ex-notes-$instanceKey'),
                initialValue: exercise.notes ?? '',
                style: context.type.paragraph.copyWith(
                  color: context.colors.ink,
                ),
                decoration: AppField.onBackground(context),
                onChanged: onNotesChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
