import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'app_audio_session.dart';

/// I suoni dell'interfaccia.
///
/// Sono un accompagnamento, non un segnale: a differenza dei beep del timer
/// ([SessionFeedback]) tacciono col telefono in silenzioso, non abbassano la
/// musica e non vibrano. Astratta per lo stesso motivo: la shell e i suoi
/// test non devono toccare plugin né platform channel.
abstract interface class UiSounds {
  /// Carica i suoni, perché il primo non arrivi in ritardo sul gesto.
  Future<void> prepare();

  /// Il "plop" della goccia che arriva sulla destinazione scelta nella tab
  /// bar. Non propaga mai eccezioni: un suono mancato non è un errore.
  Future<void> drop();

  Future<void> dispose();
}

/// Implementazione reale su `audioplayers`.
class PluginUiSounds implements UiSounds {
  PluginUiSounds({required AppAudioSession audioSession})
    : _audioSession = audioSession {
    // Di suo il player chiede la posizione a ogni fotogramma finché si crede
    // in riproduzione, e in bassa latenza la fine del suono non gli arriva
    // mai: dopo il primo plop l'app ridisegnerebbe a vuoto per sempre.
    _player.positionUpdater = null;
  }

  static const _dropAsset = 'audio/plop.wav';

  final AppAudioSession _audioSession;
  final AudioPlayer _player = AudioPlayer(playerId: 'ui-sounds');

  /// Una preparazione sola, anche se la chiedono in due: chi suona prima che
  /// sia finita la aspetta invece di rifarla.
  Future<void>? _preparing;

  @override
  Future<void> prepare() => _preparing ??= _prepare();

  Future<void> _prepare() async {
    try {
      await _audioSession.claim(AudioRole.interfaceSound);
      if (defaultTargetPlatform == TargetPlatform.android) {
        // Su Android il contesto è del player: `assistanceSonification` è
        // l'uso previsto per i suoni dell'interfaccia (segue il silenzioso),
        // e senza focus audio la musica non si accorge di niente.
        await _player.setAudioContext(
          AudioContext(
            android: const AudioContextAndroid(
              contentType: AndroidContentType.sonification,
              usageType: AndroidUsageType.assistanceSonification,
              audioFocus: AndroidAudioFocus.none,
            ),
          ),
        );
      }
      // Un suono di un sesto di secondo che deve cadere su un fotogramma
      // preciso: su Android è il mestiere di SoundPool, non di MediaPlayer.
      await _player.setPlayerMode(PlayerMode.lowLatency);
      // `stop` tiene la sorgente caricata: ogni plop è un `resume`.
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.setSource(AssetSource(_dropAsset));
    } catch (error, stackTrace) {
      _report('preparazione suoni', error, stackTrace);
    }
  }

  @override
  Future<void> drop() async {
    await prepare();
    try {
      // Dopo un allenamento la sessione audio di iOS è rimasta ai segnali
      // del timer: la si riprende, o il plop bucherebbe il silenzioso.
      await _audioSession.claim(AudioRole.interfaceSound);
      // Lo `stop` riavvolge: senza, a suono finito `resume` non ha più
      // niente da riprendere.
      await _player.stop();
      await _player.resume();
    } catch (error, stackTrace) {
      _report('riproduzione plop', error, stackTrace);
    }
  }

  @override
  Future<void> dispose() async {
    try {
      await _player.dispose();
    } catch (error, stackTrace) {
      _report('chiusura player', error, stackTrace);
    }
  }

  void _report(String what, Object error, StackTrace stackTrace) {
    // L'audio è un accessorio: si logga e si prosegue.
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'ui_sounds',
        context: ErrorDescription(what),
      ),
    );
  }
}
