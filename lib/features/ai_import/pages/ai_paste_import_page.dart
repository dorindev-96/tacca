import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/app_spacing.dart';
import '../../../core/design/linear_icons.dart';
import '../../../core/design/theme_context.dart';
import '../../../core/widgets/app_field.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_snack_bar.dart';
import '../../../core/widgets/info_banner.dart';
import '../../../core/widgets/meta_chip.dart';
import '../../../core/widgets/pill_button.dart';
import '../../../core/widgets/square_icon_button.dart';
import '../../../l10n/app_localizations.dart';
import '../cubit/ai_paste_import_cubit.dart';
import '../cubit/ai_paste_import_state.dart';
import '../cubit/shared_text_cubit.dart';
import '../widgets/image_source_picker.dart';
import 'ai_import_review_args.dart';

/// Import di una scheda passando per una chat AI qualsiasi (RF-03), in due
/// passi: si prepara il messaggio, lo si manda alla chat dal foglio di
/// condivisione, si torna con la risposta — condivisa con Tacca dalla chat
/// stessa, o incollata.
///
/// I due passi sono una sola route con uno stato dentro, non due pagine: il
/// testo della scheda, le foto e la risposta devono sopravvivere all'andirivieni
/// fra l'uno e l'altro, e "indietro" dal secondo passo deve tornare al primo,
/// non uscire dall'import buttando via tutto.
///
/// La pagina è anche chi si prende il testo condiviso con l'app
/// ([SharedTextCubit]): lo fa quando compare, perché può essere stata aperta
/// apposta da `SharedTextIntake`, e ogni volta che ne arriva uno mentre è a
/// schermo. Cosa farne lo decide il cubit, che sa in quale passo si trova.
class AiPasteImportPage extends StatefulWidget {
  const AiPasteImportPage({super.key});

  /// La route di questa pagina. Sta qui, e non solo nel router, perché
  /// `SharedTextIntake` deve riconoscerla per non aprirne una seconda sopra.
  static const String routePath = '/plans/new/import/paste';

  @override
  State<AiPasteImportPage> createState() => _AiPasteImportPageState();
}

class _AiPasteImportPageState extends State<AiPasteImportPage> {
  @override
  void initState() {
    super.initState();
    // Il testo può essere arrivato prima della pagina: ad app chiusa è
    // proprio lui ad averla fatta aprire.
    WidgetsBinding.instance.addPostFrameCallback((_) => _takeSharedText());
  }

  void _takeSharedText() {
    if (!mounted) return;
    final shared = context.read<SharedTextCubit>();
    final text = shared.state;
    if (text == null) return;
    shared.consume();
    context.read<AiPasteImportCubit>().receiveSharedText(text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return BlocListener<SharedTextCubit, String?>(
      listenWhen: (previous, current) => current != null,
      listener: (context, text) => _takeSharedText(),
      child: BlocConsumer<AiPasteImportCubit, AiPasteImportState>(
        listenWhen: (previous, current) =>
            previous.draft != current.draft && current.draft != null,
        listener: (context, state) {
          if (state.usedFallback) {
            ScaffoldMessenger.of(
              context,
            ).showMessage(l10n.aiPasteFreeTextNotice);
          }
          context.pushReplacement(
            '/plans/new/review',
            extra: AiImportReviewArgs(draft: state.draft!),
          );
        },
        builder: (context, state) {
          final cubit = context.read<AiPasteImportCubit>();
          final composing = state.step == AiPasteImportStep.compose;

          return PopScope(
            canPop: composing,
            onPopInvokedWithResult: (didPop, result) {
              if (!didPop) cubit.backToCompose();
            },
            child: AppScaffold(
              leading: composing
                  ? const AppBackButton()
                  : AppBackButton(onPressed: cubit.backToCompose),
              title: composing
                  ? l10n.aiPasteComposeTitle
                  : l10n.aiPastePasteTitle,
              header: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  0,
                  AppSpacing.xl,
                  AppSpacing.card,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: MetaChip(
                    label: composing
                        ? l10n.aiPasteStepOne
                        : l10n.aiPasteStepTwo,
                    tone: ChipTone.onBackground,
                    small: false,
                  ),
                ),
              ),
              dock: composing
                  ? PillButton(
                      label: l10n.aiPasteContinue,
                      icon: AppIcons.chevronRight,
                      onPressed: state.canContinue
                          ? () => _deliver(context, cubit.continueToPaste)
                          : null,
                    )
                  : PillButton(
                      label: l10n.aiPasteFinish,
                      icon: AppIcons.check,
                      onPressed: state.canFinish ? cubit.finish : null,
                    ),
              body: composing
                  ? _ComposeStep(state: state)
                  : _PasteStep(state: state),
            ),
          );
        },
      ),
    );
  }
}

/// Manda fuori un messaggio e dice all'utente solo ciò che non si vede da
/// sé: il foglio di condivisione che non c'era, e il testo finito negli
/// appunti al suo posto. Una condivisione riuscita non ha bisogno di avvisi
/// (l'utente è già nell'altra app) e una annullata non ha cambiato niente.
Future<void> _deliver(
  BuildContext context,
  Future<AiPasteDelivery> Function() send,
) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final delivery = await send();
  if (delivery == AiPasteDelivery.copied) {
    messenger.showMessage(l10n.aiPasteShareUnavailable);
  }
}

/// Copia negli appunti e lo dice: qui l'utente l'ha chiesto, e la conferma è
/// l'unica cosa che vede succedere.
Future<void> _copy(
  BuildContext context,
  Future<void> Function() copy,
  String notice,
) async {
  final messenger = ScaffoldMessenger.of(context);
  await copy();
  messenger.showMessage(notice);
}

/// Passo 1: la scheda. Foto lette dall'OCR del telefono e testo modificabile,
/// perché è l'ultimo momento in cui si può correggere quello che finirà in
/// una chat che il foglio non l'ha mai visto.
class _ComposeStep extends StatefulWidget {
  const _ComposeStep({required this.state});

  final AiPasteImportState state;

  @override
  State<_ComposeStep> createState() => _ComposeStepState();
}

class _ComposeStepState extends State<_ComposeStep> {
  late final TextEditingController _text = TextEditingController(
    text: widget.state.text,
  );

  @override
  void didUpdateWidget(covariant _ComposeStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Il campo è scritto anche dall'OCR e da un testo condiviso con l'app.
    _text.follow(widget.state.text);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<AiPasteImportCubit>();
    final state = widget.state;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        0,
        AppSpacing.xl,
        AppSpacing.actionClearance,
      ),
      children: [
        if (state.error == AiPasteImportError.ocrEmpty) ...[
          InfoBanner(
            tone: InfoBannerTone.alert,
            message: l10n.aiPasteOcrEmpty,
            onDismiss: cubit.dismissError,
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        InfoBanner(message: l10n.aiPasteIntro),
        const SizedBox(height: AppSpacing.xl),
        ImageSourcePicker(
          images: state.images,
          enabled: !state.isReadingImages,
          onRemove: cubit.removeImage,
          onCamera: cubit.addFromCamera,
          onGallery: cubit.addFromGallery,
        ),
        if (state.isReadingImages) ...[
          const SizedBox(height: AppSpacing.lg),
          Center(
            child: Text(
              l10n.aiPasteReadingImages,
              style: context.type.sectionLabel,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        if (state.usedOcr) ...[
          InfoBanner(message: l10n.aiPasteOcrNotice),
          const SizedBox(height: AppSpacing.card),
        ],
        LabeledField(
          label: l10n.aiPasteTextLabel,
          child: TextField(
            key: const ValueKey('paste-text'),
            controller: _text,
            style: context.type.fieldProse,
            decoration: AppField.onBackground(
              context,
              hintText: l10n.aiPasteTextHint,
            ),
            minLines: 6,
            maxLines: 16,
            onChanged: cubit.updateText,
          ),
        ),
        const SizedBox(height: AppSpacing.card),
        LabeledField(
          label: l10n.aiPasteHintLabel,
          child: TextFormField(
            key: const ValueKey('paste-hint'),
            initialValue: state.hint,
            style: context.type.row,
            decoration: AppField.onBackground(context),
            onChanged: cubit.updateHint,
          ),
        ),
        if (!state.canContinue && !state.isReadingImages) ...[
          const SizedBox(height: AppSpacing.card),
          Center(child: Text(l10n.aiPasteNoText, style: context.type.meta)),
        ],
      ],
    );
  }
}

/// Passo 2: la risposta. Arriva da sola se dalla chat la si condivide con
/// Tacca, altrimenti si incolla. Se non è utilizzabile non si perde niente —
/// si può far correggere la chat con l'errore del parser, o tenere tutto
/// come testo libero (RNF-05).
class _PasteStep extends StatefulWidget {
  const _PasteStep({required this.state});

  final AiPasteImportState state;

  @override
  State<_PasteStep> createState() => _PasteStepState();
}

class _PasteStepState extends State<_PasteStep> {
  late final TextEditingController _response = TextEditingController(
    text: widget.state.response,
  );

  @override
  void didUpdateWidget(covariant _PasteStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Il campo è scritto anche dall'incolla dagli appunti e da una risposta
    // condivisa con l'app.
    _response.follow(widget.state.response);
  }

  @override
  void dispose() {
    _response.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<AiPasteImportCubit>();
    final state = widget.state;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        0,
        AppSpacing.xl,
        AppSpacing.actionClearance,
      ),
      children: [
        InfoBanner(message: l10n.aiPastePasteIntro),
        const SizedBox(height: AppSpacing.md),
        // Condividere è la strada; copiare resta per chi preferisce incollare
        // a mano o per una chat che dal foglio non si raggiunge.
        Wrap(
          alignment: WrapAlignment.end,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            PillButton.compact(
              label: l10n.aiPasteCopyPrompt,
              icon: AppIcons.lines,
              tone: PillTone.outline,
              onPressed: () =>
                  _copy(context, cubit.copyPrompt, l10n.aiPastePromptCopied),
            ),
            PillButton.compact(
              label: l10n.aiPasteSharePromptAgain,
              tone: PillTone.outline,
              onPressed: () => _deliver(context, cubit.sharePrompt),
            ),
          ],
        ),
        if (state.error == AiPasteImportError.parse) ...[
          const SizedBox(height: AppSpacing.card),
          InfoBanner(
            tone: InfoBannerTone.alert,
            message: l10n.aiPasteParseFailed(state.parseError ?? ''),
          ),
          const SizedBox(height: AppSpacing.sm),
          PillButton(
            label: l10n.aiPasteShareCorrection,
            tone: PillTone.outline,
            onPressed: () => _deliver(context, cubit.shareCorrection),
          ),
          const SizedBox(height: AppSpacing.sm),
          PillButton(
            label: l10n.aiPasteCopyCorrection,
            icon: AppIcons.lines,
            tone: PillTone.outline,
            onPressed: () => _copy(
              context,
              cubit.copyCorrection,
              l10n.aiPasteCorrectionCopied,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          PillButton(
            label: l10n.aiPasteKeepAsFreeText,
            tone: PillTone.outline,
            onPressed: cubit.keepAsFreeText,
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        LabeledField(
          label: l10n.aiPasteResponseLabel,
          child: TextField(
            key: const ValueKey('paste-response'),
            controller: _response,
            style: context.type.fieldProse,
            decoration: AppField.onBackground(
              context,
              hintText: l10n.aiPasteResponseHint,
            ),
            minLines: 8,
            maxLines: 20,
            onChanged: cubit.updateResponse,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Align(
          alignment: Alignment.centerRight,
          child: PillButton.compact(
            label: l10n.aiPastePasteFromClipboard,
            icon: AppIcons.noteAdd,
            tone: PillTone.outline,
            onPressed: cubit.pasteResponse,
          ),
        ),
      ],
    );
  }
}

/// I campi di questa pagina li scrive anche lo stato, non solo la tastiera.
extension on TextEditingController {
  /// Si riallinea a [text] solo quando è lo stato ad averlo cambiato, mai
  /// mentre si digita: altrimenti il cursore tornerebbe in fondo a ogni
  /// battuta.
  void follow(String text) {
    if (text == this.text) return;
    value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
