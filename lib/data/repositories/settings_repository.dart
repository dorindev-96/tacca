import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Preferenze dell'utente: lingua e tema dell'interfaccia, configurazione AI
/// (RF-08) — provider scelto e, per ciascun provider, API key e modello — e
/// accettazione dell'informativa legale mostrata al primo avvio.
///
/// Key e modello sono per provider, non globali: chi ha configurato
/// OpenRouter e prova Anthropic non deve reinserire nulla tornando indietro.
/// Il repository non conosce i provider — riceve il loro id come stringa e lo
/// usa per comporre le chiavi di storage — così `data/` resta indipendente da
/// `services/ai/`.
///
/// Le key vivono esclusivamente nel secure storage nativo (Keychain / Android
/// Keystore), mai in log né negli export (RNF-03). Lingua, tema, provider,
/// modello e versione dell'informativa accettata stanno lì accanto: sono
/// singoli valori e non giustificano un secondo meccanismo di persistenza.
abstract interface class SettingsRepository {
  /// Codice della lingua scelta a mano per l'interfaccia (`it`, `de`, …);
  /// `null` quando l'utente non ha mai scelto e si segue quella del sistema.
  ///
  /// È un codice, non una `Locale`: `data/` non conosce Flutter e non deve
  /// cominciare adesso.
  Future<String?> getLocaleCode();

  /// `null` torna a seguire la lingua del sistema.
  Future<void> setLocaleCode(String? languageCode);

  /// Tema scelto a mano (`light`, `dark`); `null` quando l'utente non ha mai
  /// scelto e si segue quello del telefono.
  ///
  /// È il `name` dell'enum e non l'enum, per la stessa ragione per cui la
  /// lingua è un codice: `ThemeMode` è un tipo di Flutter, e `data/` non lo
  /// conosce.
  Future<String?> getThemeModeName();

  /// `null` torna a seguire il tema di sistema.
  Future<void> setThemeModeName(String? name);

  /// Id del provider AI scelto; `null` se l'utente non ha mai scelto (si usa
  /// il default del catalogo).
  Future<String?> getAiProviderId();

  Future<void> setAiProviderId(String? providerId);

  Future<String?> getApiKey(String providerId);

  /// `null` o stringa vuota cancellano la key salvata.
  Future<void> setApiKey(String providerId, String? key);

  /// Id del modello scelto per [providerId]; `null` se l'utente non ha mai
  /// scelto (si usa il default del provider nel catalogo).
  Future<String?> getModelId(String providerId);

  Future<void> setModelId(String providerId, String? modelId);

  /// Versione dell'informativa legale accettata al primo avvio; `null` se
  /// l'utente non ha mai accettato nulla.
  ///
  /// Sta qui, e non in una entità ObjectBox, per lo stesso motivo del
  /// modello: è una singola riga di configurazione dell'utente, non un dato
  /// del dominio.
  Future<int?> getAcceptedLegalNoticeVersion();

  Future<void> setAcceptedLegalNoticeVersion(int version);
}

class SecureSettingsRepository implements SettingsRepository {
  SecureSettingsRepository({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _localeKey = 'ui.locale';

  static const _themeModeKey = 'ui.themeMode';

  static const _providerKey = 'ai.provider';

  static const _legalNoticeKey = 'legal.acceptedNoticeVersion';

  /// Le chiavi per provider mantengono lo schema già in uso per OpenRouter
  /// (`ai.openrouter.apiKey`, `ai.openrouter.model`): chi aveva configurato
  /// l'app prima dell'arrivo degli altri provider ritrova la sua key al suo
  /// posto.
  static String _apiKeyKey(String providerId) => 'ai.$providerId.apiKey';

  static String _modelKey(String providerId) => 'ai.$providerId.model';

  @override
  Future<String?> getLocaleCode() => _read(_localeKey);

  @override
  Future<void> setLocaleCode(String? languageCode) =>
      _write(_localeKey, languageCode);

  @override
  Future<String?> getThemeModeName() => _read(_themeModeKey);

  @override
  Future<void> setThemeModeName(String? name) => _write(_themeModeKey, name);

  @override
  Future<String?> getAiProviderId() => _read(_providerKey);

  @override
  Future<void> setAiProviderId(String? providerId) =>
      _write(_providerKey, providerId);

  @override
  Future<String?> getApiKey(String providerId) => _read(_apiKeyKey(providerId));

  @override
  Future<void> setApiKey(String providerId, String? key) =>
      _write(_apiKeyKey(providerId), key);

  @override
  Future<String?> getModelId(String providerId) => _read(_modelKey(providerId));

  @override
  Future<void> setModelId(String providerId, String? modelId) =>
      _write(_modelKey(providerId), modelId);

  @override
  Future<int?> getAcceptedLegalNoticeVersion() async {
    final value = await _read(_legalNoticeKey);
    return value == null ? null : int.tryParse(value);
  }

  @override
  Future<void> setAcceptedLegalNoticeVersion(int version) =>
      _write(_legalNoticeKey, '$version');

  Future<String?> _read(String key) async {
    final value = await _storage.read(key: key);
    return (value == null || value.isEmpty) ? null : value;
  }

  Future<void> _write(String key, String? value) async {
    if (value == null || value.trim().isEmpty) {
      await _storage.delete(key: key);
    } else {
      await _storage.write(key: key, value: value.trim());
    }
  }
}
