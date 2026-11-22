import 'package:audioplayers/audioplayers.dart';

/// A cosa serve l'audio dell'app in un dato momento.
enum AudioRole {
  /// I segnali del timer (§7): sono il motivo per cui il telefono sta sulla
  /// panca, quindi si sentono anche con l'interruttore silenzioso di iOS e
  /// non fermano la musica di chi si allena.
  timerSignal,

  /// I suoni dell'interfaccia: un di più. Tacciono col telefono in
  /// silenzioso e non toccano la musica in nessun modo.
  interfaceSound;

  AudioContext get _context => switch (this) {
    AudioRole.timerSignal => AudioContext(
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.playback,
        options: const {AVAudioSessionOptions.mixWithOthers},
      ),
      android: const AudioContextAndroid(
        contentType: AndroidContentType.sonification,
        usageType: AndroidUsageType.assistanceSonification,
        audioFocus: AndroidAudioFocus.gainTransientMayDuck,
      ),
    ),
    // `ambient` rispetta l'interruttore silenzioso e si mescola da sé con
    // l'audio delle altre app.
    AudioRole.interfaceSound => AudioContext(
      iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
    ),
  };
}

/// La sessione audio dell'app, che su iOS è **una sola**.
///
/// `audioplayers` lascia impostare un contesto per player, ma su iOS dietro
/// c'è `AVAudioSession.sharedInstance()`: chi lo imposta lo cambia a tutti.
/// I segnali del timer e i suoni dell'interfaccia vogliono due cose opposte
/// (i primi bucano il silenzioso, i secondi lo rispettano), quindi serve un
/// posto solo che sappia a chi tocca: ognuno, prima di suonare, la reclama
/// per il proprio ruolo, e il cambio avviene solo se l'ultimo a suonare era
/// l'altro.
///
/// Senza, il valore di fabbrica del plugin è `playback` non mescolato: il
/// primo suono dell'interfaccia fermerebbe la musica dell'utente.
class AppAudioSession {
  AudioRole? _role;

  Future<void> claim(AudioRole role) async {
    if (_role == role) return;
    await AudioPlayer.global.setAudioContext(role._context);
    _role = role;
  }
}
