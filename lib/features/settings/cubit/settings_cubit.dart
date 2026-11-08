import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/errors/ai_failure.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../services/ai/ai_provider.dart';
import '../../../services/ai/ai_selection.dart';
import '../../../services/ai/model_catalog.dart';
import 'settings_state.dart';

/// Configurazione AI (RF-08): scelta del provider, sua API key, suo modello
/// dal catalogo JSON, test connessione.
///
/// Key e modello sono per provider: passare da OpenRouter ad Anthropic (e
/// tornare indietro) non cancella nulla, ricarica solo ciò che è salvato per
/// il provider scelto.
class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit({
    required SettingsRepository settings,
    required AiProvider provider,
    required AiSelectionResolver selection,
  }) : _settings = settings,
       _provider = provider,
       _selection = selection,
       super(const SettingsState()) {
    _load();
  }

  final SettingsRepository _settings;
  final AiProvider _provider;
  final AiSelectionResolver _selection;

  /// Catalogo di provider e modelli (da `assets/ai/models.json`), immutabile
  /// per la vita del cubit: la UI lo legge da qui.
  AiModelCatalog get catalog => _selection.catalog;

  /// Il provider mostrato in UI, con i suoi modelli.
  AiProviderOption get selectedProvider =>
      catalog.byId(state.selectedProviderId) ?? catalog.defaultProvider;

  Future<void> _load() async {
    try {
      final selection = await _selection.resolve();
      emit(
        state.copyWith(
          isLoading: false,
          selectedProviderId: selection.provider.id,
          hasApiKey: selection.isConfigured,
          selectedModelId: selection.model.id,
        ),
      );
    } catch (_) {
      // Senza dire niente la pagina si aprirebbe come se non ci fosse
      // nessuna key salvata: l'utente penserebbe di averla persa.
      emit(
        state.copyWith(isLoading: false, failure: SettingsFailure.loadFailed),
      );
    }
  }

  /// Cambia provider e ricarica key e modello salvati per quello nuovo.
  Future<void> selectProvider(AiProviderId providerId) async {
    if (providerId == state.selectedProviderId) return;
    await _settings.setAiProviderId(providerId.value);
    final selection = await _selection.resolveFor(providerId);
    emit(
      state.copyWith(
        selectedProviderId: providerId,
        hasApiKey: selection.isConfigured,
        selectedModelId: selection.model.id,
        // L'esito del test riguardava l'altra key: qui non dice più nulla.
        testStatus: AiConnectionTestStatus.idle,
        testFailure: null,
      ),
    );
  }

  Future<void> saveApiKey(String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) return;
    await _settings.setApiKey(selectedProvider.id.value, trimmed);
    emit(
      state.copyWith(
        hasApiKey: true,
        testStatus: AiConnectionTestStatus.idle,
        testFailure: null,
      ),
    );
  }

  Future<void> removeApiKey() async {
    await _settings.setApiKey(selectedProvider.id.value, null);
    emit(
      state.copyWith(
        hasApiKey: false,
        testStatus: AiConnectionTestStatus.idle,
        testFailure: null,
      ),
    );
  }

  Future<void> selectModel(String modelId) async {
    await _settings.setModelId(selectedProvider.id.value, modelId);
    emit(state.copyWith(selectedModelId: modelId));
  }

  Future<void> testConnection() async {
    emit(
      state.copyWith(
        testStatus: AiConnectionTestStatus.testing,
        testFailure: null,
      ),
    );
    try {
      await _provider.testConnection();
      emit(state.copyWith(testStatus: AiConnectionTestStatus.success));
    } catch (e) {
      emit(
        state.copyWith(
          testStatus: AiConnectionTestStatus.failure,
          testFailure: AiFailure.from(e),
        ),
      );
    }
  }
}
