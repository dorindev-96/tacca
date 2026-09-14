import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/design/theme_context.dart';
import '../cubit/legal_notice_cubit.dart';
import '../pages/legal_gate_page.dart';

/// Cancello legale davanti a tutta l'app.
///
/// Vive nel `builder` di `MaterialApp.router`, quindi sopra il router: finché
/// l'informativa non è accettata il [child] — cioè il `Router` con le
/// schermate — **non viene montato affatto**. Non è un dettaglio: se il
/// router girasse dietro l'avviso, la ripresa di una sessione interrotta
/// aprirebbe il suo dialog dietro una manleva non ancora accettata.
///
/// Durante la lettura della preferenza (pochi millisecondi) si mostra il
/// fondo dell'app: nessuno spinner che lampeggia a ogni avvio.
class LegalGate extends StatelessWidget {
  const LegalGate({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LegalNoticeCubit, LegalNoticeStatus>(
      builder: (context, status) {
        switch (status) {
          case LegalNoticeStatus.unknown:
            return ColoredBox(
              color: context.colors.background,
              child: SizedBox.expand(),
            );
          case LegalNoticeStatus.pending:
            return LegalGatePage(
              onAccept: context.read<LegalNoticeCubit>().accept,
            );
          case LegalNoticeStatus.accepted:
            return child;
        }
      },
    );
  }
}
