import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/design/app_radius.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/design/linear_icons.dart';
import '../../../core/design/theme_context.dart';
import '../../../core/widgets/app_field.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/linear_icon.dart';
import '../../../core/widgets/pill_button.dart';
import '../../../data/entities/log_set.dart';
import '../../../l10n/app_localizations.dart';

/// Esito del pannello di log rapido di una serie.
sealed class SetLogOutcome {
  const SetLogOutcome();
}

/// Valori confermati dall'utente.
class SetLogSaved extends SetLogOutcome {
  const SetLogSaved({this.weightKg, this.reps, this.notes});

  final double? weightKg;
  final String? reps;
  final String? notes;
}

/// La serie va tolta dal log (spunta annullata).
class SetLogRemoved extends SetLogOutcome {
  const SetLogRemoved();
}

/// Log rapido di una serie (RF-06): peso e ripetizioni effettivi, già
/// precompilati, con incrementi a portata di pollice per evitare la tastiera
/// quando basta ritoccare il carico.
Future<SetLogOutcome?> showSetLogSheet(
  BuildContext context, {
  required String exerciseName,
  required int setNumber,
  required LogSet? current,
  double? suggestedWeightKg,
  String? suggestedReps,
}) {
  return showAppSheet<SetLogOutcome>(
    context,
    builder: (context) => _SetLogSheet(
      exerciseName: exerciseName,
      setNumber: setNumber,
      weightKg: current?.weightKg ?? suggestedWeightKg,
      reps: current?.reps ?? suggestedReps,
      notes: current?.notes,
      canRemove: current != null,
    ),
  );
}

class _SetLogSheet extends StatefulWidget {
  const _SetLogSheet({
    required this.exerciseName,
    required this.setNumber,
    required this.weightKg,
    required this.reps,
    required this.notes,
    required this.canRemove,
  });

  final String exerciseName;
  final int setNumber;
  final double? weightKg;
  final String? reps;
  final String? notes;
  final bool canRemove;

  @override
  State<_SetLogSheet> createState() => _SetLogSheetState();
}

class _SetLogSheetState extends State<_SetLogSheet> {
  late final TextEditingController _weight = TextEditingController(
    text: _formatWeight(widget.weightKg),
  );
  late final TextEditingController _reps = TextEditingController(
    text: widget.reps ?? '',
  );
  late final TextEditingController _notes = TextEditingController(
    text: widget.notes ?? '',
  );

  static String _formatWeight(double? value) {
    if (value == null) return '';
    // I carichi in palestra sono mezzi chili: niente decimali inutili.
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
  }

  double? get _parsedWeight {
    final raw = _weight.text.trim().replaceAll(',', '.');
    if (raw.isEmpty) return null;
    return double.tryParse(raw);
  }

  void _stepWeight(double delta) {
    final next = (_parsedWeight ?? 0) + delta;
    setState(() {
      _weight.text = _formatWeight(next < 0 ? 0 : next);
    });
  }

  @override
  void dispose() {
    _weight.dispose();
    _reps.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AppSheet(
      title: l10n.workoutSetSheetTitle(widget.exerciseName, widget.setNumber),
      scrollable: true,
      children: [
        FieldLabel(l10n.workoutWeightLabel),
        // Il peso si ritocca quasi sempre di uno scatto: i due pulsanti
        // evitano di aprire la tastiera con le mani sudate (RNF-04).
        Row(
          children: [
            _StepButton(
              icon: AppIcons.minus,
              tooltip: '-2,5',
              onPressed: () => _stepWeight(-2.5),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _NumberField(
                fieldKey: const ValueKey('set-weight'),
                controller: _weight,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            _StepButton(
              icon: AppIcons.add,
              tooltip: '+2,5',
              onPressed: () => _stepWeight(2.5),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.card),
        FieldLabel(l10n.workoutRepsLabel),
        _NumberField(fieldKey: const ValueKey('set-reps'), controller: _reps),
        const SizedBox(height: AppSpacing.card),
        FieldLabel(l10n.workoutSetNotesLabel),
        TextField(
          key: const ValueKey('set-notes'),
          controller: _notes,
          style: context.type.paragraph.copyWith(color: context.colors.ink),
          decoration: AppField.inset(context),
        ),
        const SizedBox(height: AppSpacing.card),
        Row(
          children: [
            if (widget.canRemove) ...[
              PillButton(
                label: l10n.workoutRemoveSet,
                tone: PillTone.danger,
                expand: false,
                onPressed: () =>
                    Navigator.of(context).pop(const SetLogRemoved()),
              ),
              const SizedBox(width: AppSpacing.md),
            ],
            Expanded(
              child: PillButton(
                label: l10n.commonSave,
                onPressed: () => Navigator.of(context).pop(
                  SetLogSaved(
                    weightKg: _parsedWeight,
                    reps: _blankToNull(_reps.text),
                    notes: _blankToNull(_notes.text),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String? _blankToNull(String value) =>
      value.trim().isEmpty ? null : value.trim();
}

/// Campo numerico grande e centrato: si legge da lontano e si corregge con
/// un pollice solo.
class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.fieldKey,
    required this.controller,
    this.autofocus = false,
    this.keyboardType,
    this.inputFormatters,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final bool autofocus;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: TextField(
        key: fieldKey,
        controller: controller,
        autofocus: autofocus,
        textAlign: TextAlign.center,
        style: context.type.numericField,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        decoration: AppField.inset(context, contentPadding: EdgeInsets.zero),
      ),
    );
  }
}

/// Pulsante di incremento/decremento del carico: quadrato e grande, si
/// centra col pollice senza guardare.
class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final LinearIconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: context.colors.fill,
        borderRadius: BorderRadius.circular(AppRadius.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox.square(
            dimension: 56,
            child: Center(child: LinearIcon(icon, size: 24)),
          ),
        ),
      ),
    );
  }
}
