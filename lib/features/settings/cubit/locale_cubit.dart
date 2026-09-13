import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/repositories/settings_repository.dart';

/// Lingua dell'interfaccia scelta a mano; `null` significa "quella del
/// sistema", che è anche il default.
///
/// `null` non è uno stato di comodo: è esattamente ciò che `MaterialApp.locale`
/// vuole per lasciar decidere al telefono, quindi lo stato di questo cubit si
/// passa al `MaterialApp` così com'è.
///
/// Vive nella composition root, sopra al router, perché il suo lettore è
/// `MaterialApp` stesso. Durante la lettura della preferenza (pochi
/// millisecondi) lo stato è `null` e vale la lingua di sistema: nessun lampo
/// visibile, perché fino ad allora il gate legale disegna solo il fondo.
class LocaleCubit extends Cubit<Locale?> {
  LocaleCubit({required SettingsRepository settings})
    : _settings = settings,
      super(null) {
    _load();
  }

  final SettingsRepository _settings;

  Future<void> _load() async {
    String? code;
    try {
      code = await _settings.getLocaleCode();
    } on Exception {
      // Storage illeggibile: si segue il sistema, come al primo avvio.
      code = null;
    }
    if (isClosed || code == null) return;
    emit(Locale(code));
  }

  /// Fissa la lingua dell'interfaccia; [locale] `null` torna a seguire il
  /// sistema.
  ///
  /// Lo stato cambia subito e il salvataggio segue: la lingua è una
  /// preferenza, non un dato da perdere se il keychain fa i capricci, e
  /// vedere l'app cambiare lingua al tocco è tutto il punto.
  Future<void> select(Locale? locale) async {
    if (isClosed) return;
    emit(locale);
    try {
      await _settings.setLocaleCode(locale?.languageCode);
    } on Exception {
      // Non salvata: al prossimo avvio si torna al sistema. Meglio che
      // bloccare l'utente su una schermata di errore per una preferenza.
    }
  }
}
