import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

/// Com'è finita una condivisione di testo.
enum TextShareOutcome {
  /// L'utente ha scelto un'app: il testo è arrivato a destinazione.
  shared,

  /// L'utente ha chiuso il foglio senza scegliere niente.
  dismissed,

  /// Il foglio di sistema non c'è o non sa dire com'è andata: chi chiama
  /// deve avere un piano B (gli appunti).
  unavailable,
}

/// Consegna un testo a un'altra app attraverso il foglio di condivisione di
/// sistema.
///
/// Serve all'import "con la propria AI" (RF-03, modalità senza API key): il
/// prompt non si copia negli appunti, si manda direttamente alla chat che
/// l'utente sceglie dall'elenco delle app. Come `ImageShareService` è
/// un'interfaccia perché nei widget test il plugin di piattaforma non c'è.
abstract interface class TextShareService {
  /// Apre il foglio di condivisione con [text] e dice com'è finita.
  ///
  /// [subject] è l'oggetto per le app che ne hanno uno (la posta); [originRect]
  /// è l'ancora del popover su iPad, in coordinate globali.
  Future<TextShareOutcome> share(
    String text, {
    String? subject,
    Rect? originRect,
  });
}

/// Su iOS il foglio lo presenta il nostro `TextShareBridge.swift`, altrove
/// share_plus.
///
/// Su iOS share_plus lascia l'app congelata quando l'estensione scelta
/// rimanda subito alla propria app (Gemini, scelta dalla lista "Altro"): il
/// contenitore dell'estensione resta sopra l'app, invisibile, e si prende i
/// tocchi. Il ponte nostro risponde una volta sola e, a condivisione finita
/// o al ritorno dall'altra app, chiude quello che è rimasto. Se il ponte non
/// c'è (un'app costruita senza) si ripiega su share_plus.
class SystemTextShareService implements TextShareService {
  const SystemTextShareService({MethodChannel? iosChannel})
    : _iosChannel = iosChannel ?? const MethodChannel(iosChannelName);

  static const String iosChannelName = 'tacca/text_share';

  final MethodChannel _iosChannel;

  @override
  Future<TextShareOutcome> share(
    String text, {
    String? subject,
    Rect? originRect,
  }) async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final native = await _shareOnIos(text, subject, originRect);
      if (native != null) return native;
    }
    return _shareWithPlugin(text, subject, originRect);
  }

  /// `null` quando il ponte nativo non risponde: si passa a share_plus.
  Future<TextShareOutcome?> _shareOnIos(
    String text,
    String? subject,
    Rect? originRect,
  ) async {
    final String? raw;
    try {
      raw = await _iosChannel.invokeMethod<String>('share', {
        'text': text,
        'subject': ?subject,
        if (originRect != null)
          'origin': [
            originRect.left,
            originRect.top,
            originRect.width,
            originRect.height,
          ],
      });
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return TextShareOutcome.unavailable;
    }
    return switch (raw) {
      'shared' => TextShareOutcome.shared,
      'dismissed' => TextShareOutcome.dismissed,
      _ => TextShareOutcome.unavailable,
    };
  }

  Future<TextShareOutcome> _shareWithPlugin(
    String text,
    String? subject,
    Rect? originRect,
  ) async {
    final ShareResult result;
    try {
      result = await SharePlus.instance.share(
        ShareParams(
          text: text,
          subject: subject,
          sharePositionOrigin: originRect,
        ),
      );
    } on Exception {
      return TextShareOutcome.unavailable;
    }
    return switch (result.status) {
      ShareResultStatus.success => TextShareOutcome.shared,
      ShareResultStatus.dismissed => TextShareOutcome.dismissed,
      ShareResultStatus.unavailable => TextShareOutcome.unavailable,
    };
  }
}
