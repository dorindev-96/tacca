import 'dart:typed_data';

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/extensions/blank_text.dart';
import '../../../data/entities/workout_plan.dart';

part 'ai_import_state.freezed.dart';

/// Fasi del flusso di import (§5): `input → processing → review | failure`.
/// Da `failure` si torna a `input` con foto e testo intatti (RNF-05).
enum AiImportStatus { input, processing, review, failure }

@freezed
sealed class AiImportState with _$AiImportState {
  const AiImportState._();

  const factory AiImportState({
    @Default(AiImportStatus.input) AiImportStatus status,

    /// `true` quando la presenza della key è stata verificata.
    @Default(false) bool configChecked,

    /// Key del provider selezionato presente: senza, l'import è disabilitato
    /// con spiegazione e rimando alle impostazioni (RF-08).
    @Default(false) bool isConfigured,

    /// Nome del provider selezionato, per dire *quale* key manca.
    @Default('') String providerLabel,

    /// Immagini originali scelte (bytes a piena risoluzione).
    @Default(<Uint8List>[]) List<Uint8List> images,
    @Default('') String text,
    @Default('') String hint,
    String? errorMessage,

    /// Bozza pronta per la revisione (status `review`).
    WorkoutPlan? draft,

    /// La bozza è il fallback `freeText` dopo il doppio fallimento di parsing.
    @Default(false) bool usedFallback,

    /// Le immagini sono state convertite in testo via OCR on-device perché
    /// il modello scelto non supporta le immagini (RF-03).
    @Default(false) bool usedOcr,
  }) = _AiImportState;

  bool get hasInput => images.isNotEmpty || !text.isBlank;
}
