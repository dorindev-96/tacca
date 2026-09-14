import 'package:flutter/material.dart';

import '../../../core/design/app_spacing.dart';
import '../../../core/design/theme_context.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/pill_button.dart';
import '../../../l10n/app_localizations.dart';
import '../widgets/legal_notice_body.dart';

/// L'avviso del primo avvio: non è una schermata dell'app, è la porta.
///
/// Non ha né indietro né "chiudi": finché non si accetta, il router non
/// viene nemmeno montato (vedi `LegalGate`). L'unica azione è la pillola in
/// fondo, che registra l'accettazione della versione corrente dei termini.
class LegalGatePage extends StatelessWidget {
  const LegalGatePage({required this.onAccept, super.key});

  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AppScaffold(
      title: l10n.legalNoticeTitle,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          0,
          AppSpacing.xl,
          AppSpacing.actionClearance,
        ),
        children: [
          const LegalNoticeBody(highlightIntro: true),
          const SizedBox(height: AppSpacing.card),
          Text(l10n.legalNoticeAcceptExplainer, style: context.type.caption),
        ],
      ),
      dock: PillButton(label: l10n.legalNoticeAccept, onPressed: onAccept),
    );
  }
}
