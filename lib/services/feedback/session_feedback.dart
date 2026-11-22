import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:vibration/vibration.dart';

import '../timer/timer_engine.dart';
import 'app_audio_session.dart';

/// Resa percepibile dei segnali del timer: suono + vibrazione (§7).
///
/// Astratta perché il [TimerEngine] e il Bloc restino testabili senza plugin
/// e senza platform channel.
abstract interface class SessionFeedback {
  /// Prepara le risorse (audio precaricato, capacità di vibrazione).
  Future<void> prepare();

  /// Rende percepibile [signal]. Non deve mai propagare eccezioni: un beep
  /// mancato non può interrompere l'allenamento.
  Future<void> emit(TimerSignal signal);

  Future<void> dispose();
}

/// Implementazione reale su `audioplayers` + `vibration`.
class PluginSessionFeedback implements SessionFeedback {
  PluginSessionFeedback({required AppAudioSession audioSession})
    : _audioSession = audioSession;

  static const _intervalAsset = 'audio/beep.wav';
  static const _finishedAsset = 'audio/beep_end.wav';

  final AppAudioSession _audioSession;
  final AudioPlayer _player = AudioPlayer(playerId: 'workout-timer');
  bool _canVibrate = false;

  @override
  Future<void> prepare() async {
    try {
      // Categoria "playback": il beep si sente anche con l'interruttore
      // silenzioso su iOS, e non interrompe la musica dell'utente. Passa da
      // [AppAudioSession] perché su iOS la sessione è una sola, e i suoni
      // dell'interfaccia la vogliono diversa.
      await _audioSession.claim(AudioRole.timerSignal);
      await _player.setReleaseMode(ReleaseMode.stop);
      _canVibrate = await Vibration.hasVibrator();
    } catch (error, stackTrace) {
      _report('preparazione feedback', error, stackTrace);
    }
  }

  @override
  Future<void> emit(TimerSignal signal) async {
    final (asset, vibrationMs) = switch (signal) {
      TimerSignal.interval => (_intervalAsset, 180),
      TimerSignal.finished => (_finishedAsset, 600),
    };

    try {
      // Di norma è già sua da `prepare`: costa qualcosa solo se nel
      // frattempo ha suonato l'interfaccia.
      await _audioSession.claim(AudioRole.timerSignal);
      await _player.stop();
      await _player.play(AssetSource(asset));
    } catch (error, stackTrace) {
      _report('riproduzione beep', error, stackTrace);
    }
    if (!_canVibrate) return;
    try {
      await Vibration.vibrate(duration: vibrationMs);
    } catch (error, stackTrace) {
      _report('vibrazione', error, stackTrace);
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
        library: 'session_feedback',
        context: ErrorDescription(what),
      ),
    );
  }
}
