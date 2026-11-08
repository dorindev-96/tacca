import 'package:flutter/services.dart';

/// Testo che un'altra app ha condiviso **con** Tacca.
///
/// È il viaggio di ritorno dell'import "con la propria AI" (RF-03, modalità
/// senza API key): dalla chat l'utente tocca *Condividi* sulla risposta,
/// sceglie Tacca nell'elenco delle app, e la risposta arriva qui senza
/// passare dagli appunti. Il lato nativo (l'`intent-filter` di `MainActivity`
/// su Android, l'estensione `TaccaShare` su iOS) la tiene da parte finché il
/// Dart non la chiede: è un *pull*, non un push, perché il testo può arrivare
/// ad app spenta, quando non c'è nessun motore Dart in ascolto.
///
/// Chi chiama lo fa all'avvio e a ogni rientro in primo piano — su entrambe
/// le piattaforme l'arrivo di un testo porta l'app in primo piano — e ogni
/// testo viene restituito una volta sola.
abstract interface class SharedTextReceiver {
  /// Il testo in attesa, se c'è, e lo toglie dalla coda nativa.
  Future<String?> takePending();
}

/// Il canale verso il nativo. Senza nativo (test sull'host, desktop) non c'è
/// mai niente in attesa.
class PlatformSharedTextReceiver implements SharedTextReceiver {
  const PlatformSharedTextReceiver({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'tacca/shared_text';

  final MethodChannel _channel;

  @override
  Future<String?> takePending() async {
    try {
      final text = await _channel.invokeMethod<String>('takePending');
      return (text == null || text.trim().isEmpty) ? null : text;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
