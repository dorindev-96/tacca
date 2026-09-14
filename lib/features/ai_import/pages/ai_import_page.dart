import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/app_spacing.dart';
import '../../../core/design/linear_icons.dart';
import '../../../core/design/theme_context.dart';
import '../../../core/widgets/app_field.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/info_banner.dart';
import '../../../core/widgets/pill_button.dart';
import '../../../core/widgets/square_icon_button.dart';
import '../../../core/widgets/surface_card.dart';
import '../../../l10n/app_localizations.dart';
import '../cubit/ai_import_cubit.dart';
import '../cubit/ai_import_state.dart';
import '../widgets/plan_image_thumbnail.dart';
import 'ai_import_review_args.dart';

/// Import di una scheda via AI (RF-03): foto, immagini dalla galleria e/o
/// testo. Al termine la proposta apre l'editor (RF-02) per la revisione.
class AiImportPage extends StatelessWidget {
  const AiImportPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return BlocConsumer<AiImportCubit, AiImportState>(
      listenWhen: (previous, current) =>
          previous.status != current.status &&
          current.status == AiImportStatus.review,
      listener: (context, state) {
        final notices = <String>[
          if (state.usedOcr) l10n.aiImportOcrNotice,
          if (state.usedFallback) l10n.aiImportFallbackNotice,
        ];
        if (notices.isNotEmpty) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(notices.join(' '))));
        }
        context.pushReplacement(
          '/plans/new/review',
          extra: AiImportReviewArgs(draft: state.draft!),
        );
      },
      builder: (context, state) {
        final configured = !state.configChecked || state.isConfigured;
        final input = state.status != AiImportStatus.processing && configured;

        return AppScaffold(
          leading: const AppBackButton(),
          actions: [
            SquareIconButton(
              icon: AppIcons.info,
              tooltip: l10n.aiImportInfoTooltip,
              onPressed: () => _showImportInfoDialog(context),
            ),
          ],
          title: l10n.aiImportTitle,
          // "Digitalizza" è l'unica azione che spende: sta nella pillola in
          // fondo, staccata dal modulo, e non parte mai da sola (RNF-07).
          dock: input
              ? PillButton(
                  label: l10n.aiImportSubmit,
                  icon: AppIcons.cpu,
                  onPressed: state.hasInput
                      ? context.read<AiImportCubit>().submit
                      : null,
                )
              : null,
          body: switch (state.status) {
            AiImportStatus.processing => const _ProcessingView(),
            _ when !configured => _NotConfiguredView(
              providerLabel: state.providerLabel,
            ),
            _ => _InputView(state: state),
          },
        );
      },
    );
  }
}

/// Spiega, dietro l'"i" vicino al titolo, che foto serve e come scrivere il
/// testo — con un esempio, così chi arriva qui senza aver mai usato l'import
/// non deve indovinare il formato.
void _showImportInfoDialog(BuildContext context) {
  final l10n = AppLocalizations.of(context);

  showInfoDialog(
    context,
    title: l10n.aiImportInfoTitle,
    message: l10n.aiImportInfoBody,
    child: SurfaceCard(
      color: context.colors.fill,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.aiImportInfoExampleLabel, style: context.type.sectionLabel),
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.aiImportInfoExampleText,
            style: context.type.paragraphSmall,
          ),
        ],
      ),
    ),
  );
}

/// Le funzioni AI non si nascondono: si spiegano e si rimanda alle
/// impostazioni (RF-08).
///
/// Chi arriva qui senza key non deve però trovare un vicolo cieco: procurarsi
/// una key è un viaggio, mentre l'import via chat esterna funziona adesso.
/// Per questo è lui la pillola scura, e le impostazioni restano l'alternativa.
class _NotConfiguredView extends StatelessWidget {
  const _NotConfiguredView({required this.providerLabel});

  /// Il provider scelto: la spiegazione dice *quale* key manca.
  final String providerLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return EmptyState(
      icon: AppIcons.lock,
      message: l10n.aiImportNotConfiguredBody(providerLabel),
      action: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PillButton(
            label: l10n.aiImportUseExternalChat,
            icon: AppIcons.cpu,
            expand: false,
            onPressed: () => context.pushReplacement('/plans/new/import/paste'),
          ),
          const SizedBox(height: AppSpacing.sm),
          PillButton(
            label: l10n.aiImportGoToSettings,
            icon: AppIcons.settings,
            tone: PillTone.outline,
            expand: false,
            onPressed: () async {
              final cubit = context.read<AiImportCubit>();
              await context.push('/settings/ai');
              await cubit.refreshConfiguration();
            },
          ),
        ],
      ),
    );
  }
}

class _ProcessingView extends StatelessWidget {
  const _ProcessingView();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: AppSpacing.xl),
          Text(l10n.aiImportProcessing, style: context.type.sectionLabel),
        ],
      ),
    );
  }
}

class _InputView extends StatelessWidget {
  const _InputView({required this.state});

  final AiImportState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<AiImportCubit>();

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        0,
        AppSpacing.xl,
        AppSpacing.actionClearance,
      ),
      children: [
        if (state.errorMessage != null) ...[
          InfoBanner(
            tone: InfoBannerTone.alert,
            message: state.errorMessage!,
            onDismiss: cubit.dismissError,
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        // Avviso privacy: le immagini/testi inviati lasciano il dispositivo,
        // verso il provider scelto nelle impostazioni. Aspetta di sapere
        // quale: nominarlo è metà dell'avviso.
        if (state.configChecked) ...[
          InfoBanner(
            message: l10n.aiSettingsPrivacyNotice(state.providerLabel),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
        if (state.images.isNotEmpty) ...[
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (var i = 0; i < state.images.length; i++)
                PlanImageThumbnail(
                  key: ValueKey('import-image-$i'),
                  bytes: state.images[i],
                  onRemove: () => cubit.removeImage(i),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        Row(
          children: [
            Expanded(
              child: PillButton(
                label: l10n.aiImportSourceCamera,
                icon: AppIcons.camera,
                tone: PillTone.outline,
                onPressed: cubit.addFromCamera,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: PillButton(
                label: l10n.aiImportSourceGallery,
                icon: AppIcons.gallery,
                tone: PillTone.outline,
                onPressed: cubit.addFromGallery,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        LabeledField(
          label: l10n.aiImportTextLabel,
          child: TextFormField(
            key: const ValueKey('import-text'),
            initialValue: state.text,
            style: context.type.paragraph.copyWith(color: context.colors.ink),
            decoration: AppField.onBackground(
              context,
              hintText: l10n.aiImportTextHint,
            ),
            minLines: 4,
            maxLines: 12,
            onChanged: cubit.updateText,
          ),
        ),
        const SizedBox(height: AppSpacing.card),
        LabeledField(
          label: l10n.aiImportHintLabel,
          child: TextFormField(
            key: const ValueKey('import-hint'),
            initialValue: state.hint,
            style: context.type.row,
            decoration: AppField.onBackground(context),
            onChanged: cubit.updateHint,
          ),
        ),
        if (!state.hasInput) ...[
          const SizedBox(height: AppSpacing.card),
          Center(child: Text(l10n.aiImportNoInput, style: context.type.meta)),
        ],
      ],
    );
  }
}
