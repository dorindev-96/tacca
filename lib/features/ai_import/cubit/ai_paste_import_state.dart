import 'dart:typed_data';

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/extensions/blank_text.dart';
import '../../../data/entities/workout_plan.dart';

part 'ai_paste_import_state.freezed.dart';

/// I due passi del flusso guidato (RF-03, modalità senza API key): si prepara
/// il messaggio da mandare alla chat, poi si riporta indietro la risposta.
enum AiPasteImportStep { compose, paste }

/// Cosa è andato storto, senza dire *come* raccontarlo: il testo lo sceglie
/// la pagina, che è l'unica a poter leggere le ARB.
///
/// Fa eccezione l'errore di parsing, che si porta dietro il messaggio del
/// [PlanParser] in `parseError`: quello non è testo d'interfaccia, è ciò che
/// va rimandato alla chat perché si corregga.
enum AiPasteImportError { ocrEmpty, parse }

/// Com'è uscito dall'app un messaggio per la chat (il prompt, la correzione).
///
/// Lo restituiscono i metodi del cubit che lo mandano fuori, perché la pagina
/// deve dire all'utente cosa è successo — e in particolare quando il foglio
/// di condivisione non c'era e il testo è finito negli appunti al suo posto.
enum AiPasteDelivery {
  /// Consegnato all'app scelta nel foglio di condivisione.
  shared,

  /// Messo negli appunti: perché l'utente l'ha chiesto, o perché il foglio
  /// di condivisione non era disponibile.
  copied,

  /// L'utente ha chiuso il foglio senza scegliere niente: non è uscito
  /// niente e non cambia niente.
  cancelled,
}

@freezed
sealed class AiPasteImportState with _$AiPasteImportState {
  const AiPasteImportState._();

  const factory AiPasteImportState({
    @Default(AiPasteImportStep.compose) AiPasteImportStep step,

    /// Foto scelte: qui non vengono mandate a nessuno, restano per essere
    /// allegate alla scheda come nell'import automatico (RF-03).
    @Default(<Uint8List>[]) List<Uint8List> images,

    /// Il testo della scheda: scritto, incollato o letto dalle foto.
    @Default('') String text,
    @Default('') String hint,

    /// Il messaggio mandato alla chat, conservato per poterlo rimandare o
    /// copiare dal secondo passo.
    @Default('') String prompt,

    /// La risposta della chat: incollata dall'utente o arrivata da sola,
    /// condivisa con l'app dalla chat.
    @Default('') String response,
    @Default(false) bool isReadingImages,
    @Default(false) bool isParsing,
    AiPasteImportError? error,

    /// Messaggio del parser sull'ultimo tentativo fallito.
    String? parseError,

    /// Almeno una foto è stata letta con l'OCR del telefono.
    @Default(false) bool usedOcr,

    /// Bozza pronta per la revisione: la pagina apre l'editor (RF-02).
    WorkoutPlan? draft,

    /// La bozza è la risposta grezza conservata come testo libero (RNF-05).
    @Default(false) bool usedFallback,
  }) = _AiPasteImportState;

  /// Senza testo non c'è niente da far leggere a una chat: le foto da sole
  /// non bastano, perché alla chat va del testo.
  bool get canContinue => !text.isBlank && !isReadingImages;

  bool get canFinish => !response.isBlank && !isParsing;
}
