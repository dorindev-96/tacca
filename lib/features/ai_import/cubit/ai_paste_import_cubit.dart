import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/extensions/blank_text.dart';
import '../../../services/ai/dto/plan_dto.dart';
import '../../../services/ai/plan_parser.dart';
import '../../../services/ai/prompts.dart';
import '../../../services/clipboard/clipboard_service.dart';
import '../../../services/images/image_input.dart';
import '../../../services/images/ocr_service.dart';
import '../../../services/images/plan_image_store.dart';
import 'ai_paste_import_state.dart';

/// Import di una scheda passando per una chat AI qualsiasi (RF-03, modalità
/// senza API key).
///
/// L'app non chiama nessun modello: prepara il messaggio, lo mette negli
/// appunti e aspetta che l'utente torni con la risposta. Tutto ciò che
/// richiede rete o una key resta fuori — questa strada funziona su un'app
/// appena installata, ed è l'unica che funziona se il provider è a pagamento
/// e l'utente non ne ha uno.
///
/// La risposta incollata passa dalla stessa pipeline dell'import automatico
/// (§6.2): estrazione del JSON, validazione, normalizzazione, mapping. Quello
/// che cambia è solo chi corregge quando il JSON non va: qui non c'è un retry
/// automatico, c'è un messaggio da riportare nella chat.
class AiPasteImportCubit extends Cubit<AiPasteImportState> {
  AiPasteImportCubit({
    required ImageInput imageInput,
    required PlanImageStore imageStore,
    required OcrService ocr,
    required ClipboardService clipboard,
    PlanParser parser = const PlanParser(),
  }) : _imageInput = imageInput,
       _imageStore = imageStore,
       _ocr = ocr,
       _clipboard = clipboard,
       _parser = parser,
       super(const AiPasteImportState());

  final ImageInput _imageInput;
  final PlanImageStore _imageStore;
  final OcrService _ocr;
  final ClipboardService _clipboard;
  final PlanParser _parser;

  Future<void> addFromCamera() async {
    final bytes = await _imageInput.takePhoto();
    if (bytes == null) return;
    await _addImages([bytes]);
  }

  Future<void> addFromGallery() async {
    final picked = await _imageInput.pickFromGallery();
    if (picked.isEmpty) return;
    await _addImages(picked);
  }

  void removeImage(int index) {
    if (index < 0 || index >= state.images.length) return;
    final images = [...state.images]..removeAt(index);
    emit(state.copyWith(images: images));
  }

  void updateText(String text) => emit(state.copyWith(text: text));

  void updateHint(String hint) => emit(state.copyWith(hint: hint));

  void updateResponse(String response) =>
      emit(state.copyWith(response: response));

  /// Costruisce il prompt, lo mette negli appunti e passa al secondo passo.
  ///
  /// Copiare *è* l'azione del primo passo: separare "copia" da "avanti"
  /// lascerebbe arrivare al secondo passo con gli appunti vuoti, e la pagina
  /// non avrebbe più modo di dire cosa è andato storto.
  Future<void> continueToPaste() async {
    if (!state.canContinue) return;
    final prompt = externalChatPrompt(
      text: state.text,
      userHint: state.hint.trimmedOrNull,
    );
    await _clipboard.write(prompt);
    emit(
      state.copyWith(
        step: AiPasteImportStep.paste,
        prompt: prompt,
        error: null,
      ),
    );
  }

  void backToCompose() {
    emit(state.copyWith(step: AiPasteImportStep.compose, error: null));
  }

  Future<void> copyPrompt() async {
    if (state.prompt.isEmpty) return;
    await _clipboard.write(state.prompt);
  }

  /// Il messaggio correttivo da riportare nella stessa chat: è il retry
  /// automatico del flusso via API, fatto a mano.
  Future<void> copyCorrection() async {
    final parseError = state.parseError;
    if (parseError == null) return;
    await _clipboard.write(externalChatCorrection(parseError));
  }

  /// Incolla la risposta dagli appunti: è il gesto naturale al ritorno
  /// dall'app della chat.
  Future<void> pasteResponse() async {
    final text = await _clipboard.read();
    if (text == null || text.isBlank) return;
    emit(state.copyWith(response: text, error: null, parseError: null));
  }

  Future<void> finish() async {
    if (!state.canFinish) return;
    emit(state.copyWith(isParsing: true, error: null, parseError: null));
    final PlanDto dto;
    try {
      dto = _parser.parse(state.response);
    } on PlanParseException catch (e) {
      emit(
        state.copyWith(
          isParsing: false,
          error: AiPasteImportError.parse,
          parseError: e.message,
        ),
      );
      return;
    }
    await _emitDraft(dto, usedFallback: false);
  }

  /// L'ultima uscita quando la chat non ne vuole sapere di rispondere in JSON
  /// (RNF-05): la risposta diventa un blocco di testo libero da sistemare
  /// nell'editor, invece di essere buttata.
  Future<void> keepAsFreeText() async {
    if (state.response.isBlank || state.isParsing) return;
    emit(state.copyWith(isParsing: true));
    await _emitDraft(_parser.fallback(state.response), usedFallback: true);
  }

  void dismissError() => emit(state.copyWith(error: null));

  /// Le foto entrano già lette: qui non c'è nessun modello a cui mandarle,
  /// quindi l'OCR del telefono è l'unico modo perché finiscano nel prompt.
  ///
  /// Il testo riconosciuto va in coda al campo, dove l'utente lo vede e lo
  /// corregge prima di copiare: l'OCR sbaglia, e questa è l'unica occasione
  /// per accorgersene — dopo, il testo è già in una chat che non sa cosa
  /// c'era scritto davvero sul foglio.
  Future<void> _addImages(List<Uint8List> added) async {
    emit(
      state.copyWith(
        images: [...state.images, ...added],
        isReadingImages: true,
        error: null,
      ),
    );

    // Una foto illeggibile non deve far perdere le altre (RNF-05).
    final recognized = [
      for (final page in await _ocr.recognizePages(added))
        if (page.isNotEmpty) page,
    ];

    if (recognized.isEmpty) {
      emit(
        state.copyWith(
          isReadingImages: false,
          error: AiPasteImportError.ocrEmpty,
        ),
      );
      return;
    }

    emit(
      state.copyWith(
        isReadingImages: false,
        usedOcr: true,
        text: [
          if (!state.text.isBlank) state.text.trimRight(),
          ...recognized,
        ].join('\n\n'),
      ),
    );
  }

  Future<void> _emitDraft(PlanDto dto, {required bool usedFallback}) async {
    final imagePaths = <String>[];
    for (final bytes in state.images) {
      // Un allegato che non si scrive non vale la scheda appena ottenuta:
      // la bozza va avanti lo stesso, il testo è già dentro.
      try {
        imagePaths.add(await _imageStore.saveOriginal(bytes));
      } catch (_) {
        continue;
      }
    }

    final draft = _parser.toEntity(dto, imagePaths: imagePaths);
    if (draft.name.isBlank) draft.name = 'Scheda importata';

    emit(
      state.copyWith(
        isParsing: false,
        draft: draft,
        usedFallback: usedFallback,
      ),
    );
  }
}
