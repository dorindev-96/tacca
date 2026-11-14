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
import '../../../services/share/text_share_service.dart';
import 'ai_paste_import_state.dart';

/// Import di una scheda passando per una chat AI qualsiasi (RF-03, modalità
/// senza API key).
///
/// L'app non chiama nessun modello: prepara il messaggio, lo consegna alla
/// chat che l'utente sceglie dal foglio di condivisione di sistema e aspetta
/// che torni la risposta — condivisa con l'app dalla chat stessa
/// ([receiveSharedText]) o incollata a mano. Tutto ciò che richiede rete o
/// una key resta fuori: questa strada funziona su un'app appena installata,
/// ed è l'unica che funziona se il provider è a pagamento e l'utente non ne
/// ha uno.
///
/// La risposta passa dalla stessa pipeline dell'import automatico (§6.2):
/// estrazione del JSON, validazione, normalizzazione, mapping. Quello che
/// cambia è solo chi corregge quando il JSON non va: qui non c'è un retry
/// automatico, c'è un messaggio da riportare nella chat.
///
/// Gli appunti restano il piano B: quando il foglio di condivisione non c'è
/// ([TextShareOutcome.unavailable]) il testo ci finisce da solo, e dal
/// secondo passo si può sempre copiare a mano.
class AiPasteImportCubit extends Cubit<AiPasteImportState> {
  AiPasteImportCubit({
    required ImageInput imageInput,
    required PlanImageStore imageStore,
    required OcrService ocr,
    required TextShareService share,
    required ClipboardService clipboard,
    PlanParser parser = const PlanParser(),
  }) : _imageInput = imageInput,
       _imageStore = imageStore,
       _ocr = ocr,
       _share = share,
       _clipboard = clipboard,
       _parser = parser,
       super(const AiPasteImportState());

  final ImageInput _imageInput;
  final PlanImageStore _imageStore;
  final OcrService _ocr;
  final TextShareService _share;
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

  /// Costruisce il prompt, lo manda alla chat scelta dal foglio di
  /// condivisione e passa al secondo passo.
  ///
  /// Mandarlo *è* l'azione del primo passo: separare "manda" da "avanti"
  /// lascerebbe arrivare al secondo passo senza che la chat abbia ricevuto
  /// niente. Per la stessa ragione un foglio chiuso senza scegliere
  /// ([AiPasteDelivery.cancelled]) lascia tutto com'è: non è uscito niente,
  /// non c'è niente da aspettare.
  Future<AiPasteDelivery> continueToPaste() async {
    if (!state.canContinue) return AiPasteDelivery.cancelled;
    final prompt = externalChatPrompt(
      text: state.text,
      userHint: state.hint.trimmedOrNull,
    );
    final delivery = await _deliver(prompt);
    if (delivery == AiPasteDelivery.cancelled) return delivery;
    emit(
      state.copyWith(
        step: AiPasteImportStep.paste,
        prompt: prompt,
        error: null,
      ),
    );
    return delivery;
  }

  void backToCompose() {
    emit(state.copyWith(step: AiPasteImportStep.compose, error: null));
  }

  /// Rimanda il prompt del primo passo, per chi ha chiuso la chat senza
  /// incollarlo o vuole provarne un'altra.
  Future<AiPasteDelivery> sharePrompt() async {
    if (state.prompt.isEmpty) return AiPasteDelivery.cancelled;
    return _deliver(state.prompt);
  }

  Future<void> copyPrompt() async {
    if (state.prompt.isEmpty) return;
    await _clipboard.write(state.prompt);
  }

  /// Il messaggio correttivo da riportare nella stessa chat: è il retry
  /// automatico del flusso via API, fatto a mano.
  Future<AiPasteDelivery> shareCorrection() async {
    final parseError = state.parseError;
    if (parseError == null) return AiPasteDelivery.cancelled;
    return _deliver(externalChatCorrection(parseError));
  }

  Future<void> copyCorrection() async {
    final parseError = state.parseError;
    if (parseError == null) return;
    await _clipboard.write(externalChatCorrection(parseError));
  }

  /// Incolla la risposta dagli appunti, per chi dalla chat ha copiato invece
  /// di condividere.
  Future<void> pasteResponse() async {
    final text = await _clipboard.read();
    if (text == null || text.isBlank) return;
    emit(state.copyWith(response: text, error: null, parseError: null));
  }

  /// Un testo che un'altra app ha condiviso con Tacca mentre questo import
  /// era aperto, o che l'ha fatto aprire.
  ///
  /// Nel secondo passo si sta aspettando la risposta della chat, e qualunque
  /// cosa arrivi è quella. Nel primo passo decide il contenuto: un oggetto
  /// JSON dentro è una risposta — la chat l'ha mandata mentre l'utente era
  /// tornato indietro, o l'app era chiusa — e si va avanti; un testo senza è
  /// una scheda arrivata da Note o da una chat con l'allenatore, e va nel
  /// campo del primo passo, in coda a quello che c'è già.
  ///
  /// Una risposta si legge subito, senza aspettare *Fine*: è il punto del
  /// viaggio di ritorno, l'utente non deve fare niente. Se non si legge, il
  /// secondo passo mostra l'errore e le sue due uscite come se l'avesse
  /// incollata a mano.
  Future<void> receiveSharedText(String text) async {
    if (text.isBlank || state.isParsing) return;
    final isResponse =
        state.step == AiPasteImportStep.paste ||
        _parser.containsJsonObject(text);
    if (!isResponse) {
      emit(
        state.copyWith(
          text: [
            if (!state.text.isBlank) state.text.trimRight(),
            text.trim(),
          ].join('\n\n'),
          error: null,
        ),
      );
      return;
    }
    emit(
      state.copyWith(
        step: AiPasteImportStep.paste,
        response: text,
        error: null,
        parseError: null,
      ),
    );
    await finish();
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

  /// Porta [text] fuori dall'app: dal foglio di condivisione, e negli appunti
  /// se il foglio non c'è. Non copia *anche* quando la condivisione riesce:
  /// Android annuncia ogni scrittura negli appunti, e un "copiato" dopo aver
  /// scelto un'app direbbe che è successo qualcos'altro.
  Future<AiPasteDelivery> _deliver(String text) async {
    switch (await _share.share(text)) {
      case TextShareOutcome.shared:
        return AiPasteDelivery.shared;
      case TextShareOutcome.dismissed:
        return AiPasteDelivery.cancelled;
      case TextShareOutcome.unavailable:
        await _clipboard.write(text);
        return AiPasteDelivery.copied;
    }
  }

  /// Le foto entrano già lette: qui non c'è nessun modello a cui mandarle,
  /// quindi l'OCR del telefono è l'unico modo perché finiscano nel prompt.
  ///
  /// Il testo riconosciuto va in coda al campo, dove l'utente lo vede e lo
  /// corregge prima di mandarlo: l'OCR sbaglia, e questa è l'unica occasione
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

    emit(
      state.copyWith(
        isParsing: false,
        draft: draft,
        usedFallback: usedFallback,
      ),
    );
  }
}
