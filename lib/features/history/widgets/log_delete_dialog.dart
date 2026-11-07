import 'package:flutter/widgets.dart';

import '../../../core/widgets/confirm_dialog.dart';
import '../../../data/entities/workout_log.dart';
import '../../../l10n/app_localizations.dart';

/// La conferma prima di eliminare la sessione [log], uguale dall'elenco e
/// dal dettaglio: `true` se l'utente ha confermato.
Future<bool> confirmLogDelete(BuildContext context, WorkoutLog log) {
  final l10n = AppLocalizations.of(context);
  return showConfirmDialog(
    context,
    title: l10n.historyDeleteConfirmTitle,
    message: l10n.historyDeleteConfirmBody(log.startedAt),
    confirmLabel: l10n.commonDelete,
    destructive: true,
  );
}
