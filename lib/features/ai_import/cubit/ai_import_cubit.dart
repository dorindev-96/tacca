import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/errors/ai_exception.dart';
import '../../../core/errors/ai_failure.dart';
import '../../../core/extensions/blank_text.dart';
import '../../../services/ai/ai_provider.dart';
import '../../../services/ai/ai_selection.dart';
import '../../../services/ai/plan_parser.dart';
import '../../../services/ai/prompts.dart';
import '../../../services/images/image_input.dart';
import '../../../services/images/ocr_service.dart';
import '../../../services/images/plan_image_store.dart';
import 'ai_import_state.dart';

/// Import di una scheda via AI (RF-03): foto da fotocamera, immagini dalla
/// galleria e/o testo incollato → proposta strutturata da rivedere
/// nell'editor. Nessuna chiamata parte senza il tap esplicito su
/// "Digitalizza" (RNF-07); in caso di errore foto e testo restano nello
/// stato per riprovare (RNF-05).
class AiImportCubit extends Cubit<AiImportState> {
  AiImportCubit({
    required AiProvider provider,
    required ImageInput imageInput,
    required PlanImageStore imageStore,
    required AiSelectionResolver selection,
    required OcrService ocr,
    PlanParser parser = const PlanParser(),
  }) : _provider = provider,
       _imageInput = imageInput,
       _imageStore = imageStore,
       _selection = selection,
       _ocr = ocr,
       _parser = parser,
       super(const AiImportState()) {
    _checkConfiguration();
  }

  final AiProvider _provider;
  final ImageInput _imageInput;
  final PlanImageStore _imageStore;
  final AiSelectionResolver _selection;
  final OcrService _ocr;
  final PlanParser _parser;

  Future<void> _checkConfiguration() async {
    final selection = await _selection.resolve();
    emit(
      state.copyWith(
        configChecked: true,
        isConfigured: selection.isConfigured,
        providerLabel: selection.provider.label,
      ),
    );
  }

  /// Da richiamare al ritorno dalle impostazioni.
  Future<void> refreshConfiguration() => _checkConfiguration();

  Future<void> addFromCamera() async {
    final bytes = await _imageInput.takePhoto();
    if (bytes == null) return;
    emit(
      state.copyWith(
        images: [...state.images, bytes],
        status: AiImportStatus.input,
        failure: null,
      ),
    );
  }

  Future<void> addFromGallery() async {
    final picked = await _imageInput.pickFromGallery();
    if (picked.isEmpty) return;
    emit(
      state.copyWith(
        images: [...state.images, ...picked],
        status: AiImportStatus.input,
        failure: null,
      ),
    );
  }

  void removeImage(int index) {
    if (index < 0 || index >= state.images.length) return;
    final images = [...state.images]..removeAt(index);
    emit(state.copyWith(images: images));
  }

  void updateText(String text) => emit(state.copyWith(text: text));

  void updateHint(String hint) => emit(state.copyWith(hint: hint));

  Future<void> submit() async {
    if (!state.hasInput || state.status == AiImportStatus.processing) return;

    emit(state.copyWith(status: AiImportStatus.processing, failure: null));
    try {
      var images = state.images;
      var text = state.text.trimmedOrNull;
      var usedOcr = false;

      if (images.isNotEmpty) {
        final model = (await _selection.resolve()).model;
        if (!model.supportsVision) {
          // Il modello non accetta immagini: le leggiamo noi via OCR
          // on-device e mandiamo solo testo, invece di bloccare l'import.
          final ocrText = await _recognizeText(images);
          if (ocrText.isEmpty) {
            emit(
              state.copyWith(
                status: AiImportStatus.failure,
                failure: AiFailure.imagesUnreadable,
              ),
            );
            return;
          }
          usedOcr = true;
          text = [ocrText, if (text != null) text].join('\n\n');
          images = const [];
        }
      }

      // Compressione prima dell'upload (§6.4); gli originali restano a piena
      // risoluzione su disco, allegati alla scheda (RF-03).
      final compressed = <AiImage>[
        for (final bytes in images)
          AiImage(await _imageStore.compressForUpload(bytes)),
      ];
      final extraction = await _provider.extractPlan(
        images: compressed,
        text: text,
        userHint: state.hint.trimmedOrNull,
      );

      final imagePaths = <String>[
        for (final bytes in state.images) await _imageStore.saveOriginal(bytes),
      ];
      final draft = _parser.toEntity(extraction.plan, imagePaths: imagePaths);

      emit(
        state.copyWith(
          status: AiImportStatus.review,
          draft: draft,
          usedFallback: extraction.usedFallback,
          usedOcr: usedOcr,
        ),
      );
    } on AiConfigurationException {
      emit(state.copyWith(status: AiImportStatus.input, isConfigured: false));
    } catch (e) {
      emit(
        state.copyWith(
          status: AiImportStatus.failure,
          failure: AiFailure.from(e),
        ),
      );
    }
  }

  void dismissError() {
    emit(state.copyWith(status: AiImportStatus.input, failure: null));
  }

  /// Il testo delle foto, pagina per pagina; le pagine illeggibili restano
  /// fuori senza far fallire le altre (RNF-05).
  Future<String> _recognizeText(List<Uint8List> images) async {
    final pages = await _ocr.recognizePages(images);
    return [
      for (final (i, page) in pages.indexed)
        if (page.isNotEmpty)
          pages.length == 1
              ? page
              : '${ocrPageHeader(i + 1, pages.length)}\n$page',
    ].join('\n\n');
  }
}
