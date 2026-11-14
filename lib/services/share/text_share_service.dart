import 'package:flutter/widgets.dart';
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

class SystemTextShareService implements TextShareService {
  const SystemTextShareService();

  @override
  Future<TextShareOutcome> share(
    String text, {
    String? subject,
    Rect? originRect,
  }) async {
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
