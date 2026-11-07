import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../services/ai/ai_provider.dart';

part 'settings_state.freezed.dart';

/// Esito del "test connessione" (RF-08).
enum AiConnectionTestStatus { idle, testing, success, failure }

/// Perché la pagina non mostra le impostazioni salvate: alla pagina serve
/// solo per scegliere il messaggio, come `BackupFailure`.
enum SettingsFailure {
  /// Il secure storage non ha risposto all'apertura: provider, key e modello
  /// in pagina sono i default, non quelli dell'utente.
  loadFailed,
}

/// Stato della configurazione AI (RF-08). La key non compare mai qui:
/// lo stato espone solo la sua presenza (RNF-03).
///
/// Key e modello sono quelli del provider selezionato: cambiando provider
/// cambiano entrambi, perché ogni provider ha le sue impostazioni salvate.
@freezed
sealed class SettingsState with _$SettingsState {
  const factory SettingsState({
    @Default(true) bool isLoading,
    AiProviderId? selectedProviderId,
    @Default(false) bool hasApiKey,
    String? selectedModelId,
    @Default(AiConnectionTestStatus.idle) AiConnectionTestStatus testStatus,
    String? testErrorMessage,

    /// Il caricamento iniziale non è riuscito. Resta finché la pagina è
    /// aperta: descrive i valori mostrati, non un evento passato, e non si
    /// chiude perché smetterebbe di essere vero solo rileggendo.
    SettingsFailure? failure,
  }) = _SettingsState;
}
