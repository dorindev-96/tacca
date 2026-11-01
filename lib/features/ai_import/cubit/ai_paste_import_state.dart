import 'dart:typed_data';

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/extensions/blank_text.dart';
import '../../../data/entities/workout_plan.dart';

part 'ai_paste_import_state.freezed.dart';

/// I due passi del flusso guidato (RF-03, modalità senza API key): si prepara
/// il messaggio da copiare, poi si riporta indietro la risposta della chat.
enum AiPasteImportStep { compose, paste }

/// Cosa è andato storto, senza dire *come* raccontarlo: il testo lo sceglie
/// la pagina, che è l'unica a poter leggere le ARB.
///
/// Fa eccezione l'errore di parsing, che si porta dietro il messaggio del
/// [PlanParser] in `parseError`: quello non è testo d'interfaccia, è ciò che
/// va rimandato alla chat perché si corregga.
enum AiPasteImportError { ocrEmpty, parse }

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

    /// Il messaggio copiato negli appunti, conservato per poterlo ricopiare
    /// e mostrare nel secondo passo.
    @Default('') String prompt,

    /// La risposta incollata dall'utente.
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
  /// non bastano, perché negli appunti ci va del testo.
  bool get canContinue => !text.isBlank && !isReadingImages;

  bool get canFinish => !response.isBlank && !isParsing;
}
