import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/design/app_spacing.dart';
import '../../../core/design/linear_icons.dart';
import '../../../core/design/theme_context.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/info_banner.dart';
import '../../../core/widgets/pill_button.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/square_icon_button.dart';
import '../../../core/widgets/surface_card.dart';
import '../../../l10n/app_localizations.dart';
import '../cubit/backup_cubit.dart';

/// Impostazioni → Backup: l'archivio intero in un file, e ritorno.
///
/// Due azioni e una sola pillola piena: esportare è ciò per cui si viene
/// qui, ripristinare è l'eccezione (sostituisce tutto) e resta un contorno.
/// Il ripristino chiede conferma **dopo** aver letto il file, così il
/// dialog può dire che cosa arriva e che cosa se ne va.
class BackupPage extends StatelessWidget {
  const BackupPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AppScaffold(
      leading: const AppBackButton(),
      title: l10n.backupTitle,
      body: BlocConsumer<BackupCubit, BackupState>(
        listenWhen: (previous, current) =>
            current.outcome != null &&
            !identical(previous.outcome, current.outcome),
        listener: (context, state) => _showOutcome(context, state.outcome!),
        builder: (context, state) {
          final busy = state.isBusy;

          return ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              0,
              AppSpacing.xl,
              AppSpacing.tabBarClearance,
            ),
            children: [
              Text(l10n.backupIntro, style: context.type.paragraph),
              const SizedBox(height: AppSpacing.lg),
              InfoBanner(icon: AppIcons.lock, message: l10n.backupKeysNotice),
              Section(
                label: l10n.backupExportLabel,
                child: _BackupCard(
                  body: l10n.backupExportBody,
                  progress: state.activity == BackupActivity.exporting
                      ? l10n.backupExporting
                      : null,
                  action: PillButton(
                    label: l10n.backupExportAction,
                    onPressed: busy ? null : () => _export(context),
                  ),
                ),
              ),
              Section(
                label: l10n.backupRestoreLabel,
                child: _BackupCard(
                  body: l10n.backupRestoreBody,
                  // Il ripristino vero e proprio lo racconta il dialog che
                  // blocca l'app (vedi _restore): qui solo la lettura.
                  progress: state.activity == BackupActivity.reading
                      ? l10n.backupReading
                      : null,
                  action: PillButton(
                    label: l10n.backupRestoreAction,
                    tone: PillTone.outline,
                    onPressed: busy ? null : () => _restore(context),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Il rettangolo della pagina fa da ancora al foglio di condivisione su
  /// iPad, dove è un popover: senza, compare dove capita.
  Future<void> _export(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    return context.read<BackupCubit>().export(originRect: origin);
  }

  /// Sceglie il file, lo fa verificare e solo allora chiede conferma, con i
  /// conti di ciò che arriva e di ciò che verrà sostituito.
  Future<void> _restore(BuildContext context) async {
    final cubit = context.read<BackupCubit>();
    final l10n = AppLocalizations.of(context);

    final preview = await cubit.pickBackup();
    if (preview == null) return;
    if (!context.mounted) {
      await cubit.discard(preview);
      return;
    }

    final current = cubit.currentCounts();
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.backupRestoreConfirmTitle,
      message: l10n.backupRestoreConfirmBody(
        preview.createdAt,
        preview.createdAt,
        l10n.backupPlanCount(preview.plans),
        l10n.backupLogCount(preview.logs),
        l10n.backupPlanCount(current.plans),
        l10n.backupLogCount(current.logs),
      ),
      confirmLabel: l10n.backupRestoreConfirmAction,
      destructive: true,
    );

    if (!confirmed || !context.mounted) {
      await cubit.discard(preview);
      return;
    }

    // Finché il ripristino lavora l'app resta ferma: una scheda aperta o un
    // allenamento iniziato da un'altra tab nel frattempo verrebbero spazzati
    // via dalla sostituzione, e il loro salvataggio successivo riscriverebbe
    // righe che non ci sono più. Il dialog sta sul navigator radice, quindi
    // copre anche la tab bar.
    final navigator = Navigator.of(context, rootNavigator: true);
    unawaited(
      showDialog<void>(
        context: context,
        useRootNavigator: true,
        barrierDismissible: false,
        barrierColor: context.colors.scrim,
        builder: (context) => _RestoringDialog(label: l10n.backupRestoring),
      ),
    );
    try {
      await cubit.restore(preview);
    } finally {
      navigator.pop();
    }
  }

  void _showOutcome(BuildContext context, BackupOutcome outcome) {
    final l10n = AppLocalizations.of(context);
    final message = switch (outcome) {
      BackupRestored(:final plans, :final logs) => l10n.backupRestored(
        l10n.backupPlanCount(plans),
        l10n.backupLogCount(logs),
      ),
      BackupFailed(:final reason) => switch (reason) {
        BackupFailure.exportFailed => l10n.backupExportFailed,
        BackupFailure.notABackup => l10n.backupNotABackup,
        BackupFailure.newerVersion => l10n.backupNewerVersion,
        BackupFailure.damaged => l10n.backupDamaged,
        BackupFailure.readFailed => l10n.backupReadFailed,
        BackupFailure.restoreFailed => l10n.backupRestoreFailed,
      },
    };
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

/// Il ripristino in corso, sopra tutta l'app. Non si chiude né toccando
/// fuori né con il tasto indietro: lo chiude la pagina quando il ripristino
/// è finito, bene o male.
class _RestoringDialog extends StatelessWidget {
  const _RestoringDialog({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        insetPadding: const EdgeInsets.all(AppSpacing.xl),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Row(
            children: [
              const SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(child: Text(label, style: context.type.rowStrong)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Una delle due azioni: che cosa fa, il pulsante e, mentre lavora, a che
/// punto è.
class _BackupCard extends StatelessWidget {
  const _BackupCard({required this.body, required this.action, this.progress});

  final String body;
  final Widget action;

  /// Null quando questa azione non sta lavorando.
  final String? progress;

  @override
  Widget build(BuildContext context) {
    final progress = this.progress;

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(body, style: context.type.paragraph),
          const SizedBox(height: AppSpacing.lg),
          action,
          if (progress != null) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: AppSpacing.sm),
                Flexible(child: Text(progress, style: context.type.meta)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
