import Flutter
import Foundation

/// Ponte fra il Dart (`PlatformSharedTextReceiver`) e l'App Group in cui
/// l'estensione di condivisione lascia il testo ricevuto.
///
/// Fa una cosa sola, su richiesta: consegna il testo in attesa. Non spinge
/// niente verso il Dart, perché il testo può arrivare ad app spenta, quando
/// non c'è nessuno in ascolto: l'app lo chiede all'avvio e a ogni rientro in
/// primo piano, che è esattamente quando l'estensione la riapre.
final class SharedTextBridge {
  static let channelName = "tacca/shared_text"

  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: SharedTextBridge.channelName,
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "takePending":
        result(SharedTextStore.take())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
