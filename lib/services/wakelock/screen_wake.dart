import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Schermo sempre attivo durante la sessione (RF-06): in palestra il telefono
/// resta appoggiato e deve restare leggibile.
abstract interface class ScreenWake {
  Future<void> enable();
  Future<void> disable();
}

class PluginScreenWake implements ScreenWake {
  const PluginScreenWake();

  @override
  Future<void> enable() => _guard(WakelockPlus.enable);

  @override
  Future<void> disable() => _guard(WakelockPlus.disable);

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (error, stackTrace) {
      // Su una piattaforma senza wake lock la sessione deve comunque partire.
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'screen_wake',
        ),
      );
    }
  }
}
