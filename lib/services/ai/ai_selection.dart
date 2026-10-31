import '../../core/errors/ai_exception.dart';
import '../../data/repositories/settings_repository.dart';
import 'ai_provider.dart';
import 'model_catalog.dart';

/// Provider, modello e API key correnti: il risultato di mettere insieme le
/// scelte salvate nelle impostazioni e il catalogo `assets/ai/models.json`.
class AiSelection {
  final AiProviderOption provider;
  final AiModelOption model;

  /// `null` quando per questo provider non c'è ancora una key salvata.
  final String? apiKey;

  const AiSelection({required this.provider, required this.model, this.apiKey});

  bool get isConfigured => apiKey != null;

  /// La key, o l'errore tipizzato che la UI traduce in "configura l'AI".
  String requireApiKey() =>
      apiKey ??
      (throw AiConfigurationException(
        'Nessuna API key ${provider.label} configurata.',
      ));
}

/// Risolve provider, modello e key correnti a ogni chiamata.
///
/// Sta in mezzo fra [SettingsRepository] (che conosce solo stringhe) e
/// [AiModelCatalog] (che conosce solo la configurazione): è l'unico posto in
/// cui si decide cosa succede se l'utente ha salvato un provider o un modello
/// che il JSON non offre più — si ripiega sul default invece di chiamare
/// qualcosa che non esiste.
class AiSelectionResolver {
  const AiSelectionResolver({
    required SettingsRepository settings,
    required AiModelCatalog catalog,
  }) : _settings = settings,
       _catalog = catalog;

  final SettingsRepository _settings;
  final AiModelCatalog _catalog;

  AiModelCatalog get catalog => _catalog;

  /// Il provider scelto dall'utente (o il default del catalogo).
  Future<AiProviderOption> currentProvider() async =>
      _catalog.providerOrDefault(await _settings.getAiProviderId());

  /// Selezione corrente: provider scelto, suo modello, sua key.
  Future<AiSelection> resolve() async => _selectionFor(await currentProvider());

  /// Selezione di uno specifico provider, indipendentemente da quale sia
  /// quello attivo: la usano le implementazioni, che sanno chi sono.
  Future<AiSelection> resolveFor(AiProviderId id) async {
    final provider = _catalog.byId(id);
    if (provider == null) {
      throw AiConfigurationException(
        'Il provider "${id.value}" non è più fra quelli configurati in '
        '${AiModelCatalog.assetPath}.',
      );
    }
    return _selectionFor(provider);
  }

  Future<AiSelection> _selectionFor(AiProviderOption provider) async {
    final id = provider.id.value;
    return AiSelection(
      provider: provider,
      model: provider.modelOrDefault(await _settings.getModelId(id)),
      apiKey: await _settings.getApiKey(id),
    );
  }
}
