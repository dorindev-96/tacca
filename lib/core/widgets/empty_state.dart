import 'package:flutter/material.dart';

import '../design/app_spacing.dart';
import '../design/linear_icons.dart';
import '../design/theme_context.dart';
import 'linear_icon.dart';

/// Stato vuoto uniforme: disco bianco con l'icona, messaggio e — quando
/// esiste una sola cosa sensata da fare — l'azione che lo risolve.
///
/// Uno stato vuoto è una schermata a tutti gli effetti: lasciarlo come una
/// riga di testo centrata fa sembrare l'app rotta invece che nuova.
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.message,
    this.action,
    super.key,
  });

  final LinearIconData icon;
  final String message;

  /// Pulsante mostrato sotto il messaggio. Null quando l'azione è già
  /// altrove nella schermata (tipicamente la pillola in basso) e ripeterla
  /// sarebbe rumore.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 64,
              width: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: context.colors.surface,
              ),
              child: Center(
                child: LinearIcon(icon, color: context.colors.muted),
              ),
            ),
            const SizedBox(height: AppSpacing.card),
            Text(
              message,
              textAlign: TextAlign.center,
              style: context.type.sectionLabel,
            ),
            if (action != null) ...[
              const SizedBox(height: AppSpacing.xl),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
