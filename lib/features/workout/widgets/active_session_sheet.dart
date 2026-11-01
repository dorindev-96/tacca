import 'package:flutter/material.dart';

import '../../../core/design/app_spacing.dart';
import '../../../core/design/linear_icons.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../data/entities/workout_log.dart';
import '../../../l10n/app_localizations.dart';

/// Cosa fare quando si prova ad aprire una sessione mentre un'altra è ancora
/// in corso. Chiudere il pannello (`null`) lascia tutto com'è.
enum ActiveSessionChoice {
  /// Si torna dentro alla sessione già aperta.
  resume,

  /// La sessione aperta viene chiusa come interrotta e se ne apre una nuova.
  replace,
}

/// Il bivio dell'"una sessione per volta" (RF-06).
///
/// Non è una conferma: sono due strade diverse, e quella consigliata —
/// riprendere ciò che si stava facendo — è l'unica lime del pannello. La
/// seconda dice per esteso cosa succede al vecchio allenamento, perché è la
/// scelta da cui non si torna indietro.
Future<ActiveSessionChoice?> showActiveSessionSheet(
  BuildContext context, {
  required WorkoutLog active,
}) {
  return showAppSheet<ActiveSessionChoice>(
    context,
    builder: (context) {
      final l10n = AppLocalizations.of(context);

      return AppSheet(
        title: l10n.workoutConflictTitle,
        spacing: AppSpacing.sm,
        children: [
          SheetOption(
            icon: AppIcons.play,
            title: l10n.workoutConflictResume,
            subtitle: l10n.workoutConflictResumeSubtitle(
              active.planNameSnapshot,
              active.dayLabelSnapshot,
            ),
            highlighted: true,
            onTap: () => Navigator.of(context).pop(ActiveSessionChoice.resume),
          ),
          SheetOption(
            icon: AppIcons.add,
            title: l10n.workoutConflictReplace,
            subtitle: l10n.workoutConflictReplaceSubtitle,
            onTap: () => Navigator.of(context).pop(ActiveSessionChoice.replace),
          ),
        ],
      );
    },
  );
}
