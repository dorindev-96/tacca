import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/repositories/settings_repository.dart';

/// Tema dell'interfaccia scelto a mano; [ThemeMode.system] — il default —
/// significa "come il telefono".
///
/// Gemello di `LocaleCubit`, con una differenza: lì "come il sistema" è `null`,
/// perché è quello che `MaterialApp.locale` vuole; qui Flutter ha già un nome
/// per dirlo ([ThemeMode.system]), quindi lo stato non è nullable. In entrambi
/// i casi lo stato si passa al `MaterialApp` così com'è.
///
/// Vive nella composition root, sopra al router, perché il suo lettore è
/// `MaterialApp` stesso. Durante la lettura della preferenza (pochi
/// millisecondi) vale il tema di sistema: nessun lampo visibile, perché fino
/// ad allora il gate legale disegna solo il fondo.
class ThemeModeCubit extends Cubit<ThemeMode> {
  ThemeModeCubit({required SettingsRepository settings})
    : _settings = settings,
      super(ThemeMode.system) {
    _load();
  }

  final SettingsRepository _settings;

  Future<void> _load() async {
    String? name;
    try {
      name = await _settings.getThemeModeName();
    } on Exception {
      // Storage illeggibile: si segue il sistema, come al primo avvio.
      name = null;
    }
    if (isClosed || name == null) return;
    final mode = parse(name);
    if (mode != null) emit(mode);
  }

  /// Fissa il tema; [ThemeMode.system] torna a seguire il telefono.
  ///
  /// Lo stato cambia subito e il salvataggio segue: il tema è una preferenza,
  /// non un dato da perdere se il keychain fa i capricci, e vedere l'app
  /// cambiare aspetto al tocco è tutto il punto.
  Future<void> select(ThemeMode mode) async {
    if (isClosed) return;
    emit(mode);
    try {
      await _settings.setThemeModeName(
        mode == ThemeMode.system ? null : mode.name,
      );
    } on Exception {
      // Non salvato: al prossimo avvio si torna al sistema. Meglio che
      // bloccare l'utente su una schermata di errore per una preferenza.
    }
  }

  /// Il [ThemeMode] scritto in `ui.themeMode`, o `null` se quel valore non è
  /// uno di quelli che sappiamo scrivere.
  ///
  /// Un nome sconosciuto (storage manomesso, o una versione futura che ne
  /// aggiunge uno) non deve far esplodere l'avvio: vale come "mai scelto".
  @visibleForTesting
  static ThemeMode? parse(String name) {
    for (final mode in ThemeMode.values) {
      if (mode.name == name) return mode;
    }
    return null;
  }
}
