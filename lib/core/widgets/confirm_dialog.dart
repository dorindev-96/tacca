import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../design/app_spacing.dart';
import '../design/theme_context.dart';
import 'app_field.dart';
import 'pill_button.dart';

/// Conferma unica per tutta l'app: stessa struttura (titolo, spiegazione di
/// cosa succede, annulla a sinistra e azione a destra) in ogni dialog.
///
/// Le conferme distruttive colorano la pillola di conferma di rosa: è l'unico
/// punto in cui il rosa diventa un fondo e non un testo, e serve a farlo
/// notare. Il testo sopra resta inchiostro — bianco su rosa non si legge.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String? cancelLabel,
  bool destructive = false,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => _DialogFrame(
      title: title,
      children: [
        const SizedBox(height: AppSpacing.md),
        Text(message, style: context.type.paragraph),
        const SizedBox(height: AppSpacing.card),
        _DialogActions(
          cancelLabel: cancelLabel,
          confirmLabel: confirmLabel,
          confirmTone: destructive ? PillTone.dangerFilled : PillTone.primary,
          onConfirm: () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Dialog informativo con un solo pulsante di chiusura: stessa forma delle
/// altre conferme, per spiegazioni che non chiedono una decisione (es. il
/// pulsante "i" vicino a un titolo).
Future<void> showInfoDialog(
  BuildContext context, {
  required String title,
  required String message,
  Widget? child,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _DialogFrame(
      title: title,
      children: [
        const SizedBox(height: AppSpacing.md),
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(message, style: context.type.paragraph),
                if (child != null) ...[
                  const SizedBox(height: AppSpacing.card),
                  child,
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.card),
        PillButton(
          label: AppLocalizations.of(context).commonClose,
          tone: PillTone.outline,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    ),
  );
}

/// Dialog con un campo di testo (rinomina): stessa forma della conferma.
Future<String?> showTextInputDialog(
  BuildContext context, {
  required String title,
  required String label,
  required String initialValue,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _TextInputDialog(
      title: title,
      label: label,
      initialValue: initialValue,
    ),
  );
}

/// Il `TextEditingController` vive nello `State` perché sia il framework a
/// liberarlo quando l'elemento viene smontato — cioè *dopo* la transizione di
/// uscita del dialog. Disporlo a mano subito dopo `await showDialog` lo libera
/// mentre la transizione è ancora in corso e il `TextField` può ricostruirsi
/// contro un controller già distrutto.
class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog({
    required this.title,
    required this.label,
    required this.initialValue,
  });

  final String title;
  final String label;
  final String initialValue;

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _DialogFrame(
      title: widget.title,
      children: [
        const SizedBox(height: AppSpacing.card),
        TextField(
          controller: _controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: AppField.inset(context, labelText: widget.label),
          onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
        ),
        const SizedBox(height: AppSpacing.card),
        _DialogActions(
          confirmLabel: AppLocalizations.of(context).commonSave,
          onConfirm: () => Navigator.of(context).pop(_controller.text.trim()),
        ),
      ],
    );
  }
}

/// La forma di ogni dialog dell'app: titolo e poi il contenuto, dentro il
/// riquadro del tema. Velo, margini e forma vengono da `dialogTheme`.
class _DialogFrame extends StatelessWidget {
  const _DialogFrame({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: context.type.sheetTitleLong),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// Annulla a sinistra, azione a destra. Annullare chiude il dialog senza
/// risultato (cioè `null`, che le conferme leggono come "no").
class _DialogActions extends StatelessWidget {
  const _DialogActions({
    required this.confirmLabel,
    required this.onConfirm,
    this.cancelLabel,
    this.confirmTone = PillTone.primary,
  });

  final String confirmLabel;
  final VoidCallback onConfirm;
  final String? cancelLabel;
  final PillTone confirmTone;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: PillButton(
            label: cancelLabel ?? AppLocalizations.of(context).commonCancel,
            tone: PillTone.outline,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: PillButton(
            label: confirmLabel,
            tone: confirmTone,
            onPressed: onConfirm,
          ),
        ),
      ],
    );
  }
}
