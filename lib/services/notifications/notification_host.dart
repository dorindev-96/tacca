import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Icona delle notifiche Android, come la vuole `AndroidInitializationSettings`.
///
/// La nomina solo questa stringa: nella build release lo shrinking delle
/// risorse la considera inutilizzata e la elimina, a meno che non compaia in
/// `android/app/src/main/res/raw/keep.xml` — e senza icona il plugin non si
/// inizializza e nessuna notifica parte. Il test di `keep.xml` legge da qui.
const String kAndroidNotificationIcon = '@drawable/ic_notification';

/// Punto unico di inizializzazione di `flutter_local_notifications`.
///
/// Il plugin è un singleton di piattaforma e `initialize` registra **una**
/// coppia di callback per le risposte: chiamarla due volte da due servizi
/// diversi significherebbe che l'ultimo cancella i callback del primo. Qui
/// vivono il plugin, i permessi e i fusi orari; i due servizi che ne hanno
/// bisogno — i segnali del timer ([SessionNotifier]) e la notifica persistente
/// della sessione — se lo fanno passare.
class NotificationHost {
  NotificationHost({
    FlutterLocalNotificationsPlugin? plugin,
    this.onBackgroundResponse,
  }) : plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin plugin;

  /// Risposta consegnata quando il processo è stato ucciso: gira in un isolate
  /// separato, quindi deve essere una funzione top-level annotata
  /// `@pragma('vm:entry-point')`.
  final DidReceiveBackgroundNotificationResponseCallback? onBackgroundResponse;

  final _responses = StreamController<NotificationResponse>.broadcast();

  /// Tap su una notifica o su una sua azione, con l'app ancora viva. È uno
  /// stream perché i servizi interessati sono più d'uno e `initialize`
  /// accetta una sola callback.
  Stream<NotificationResponse> get responses => _responses.stream;

  bool _ready = false;

  /// `true` se il plugin è utilizzabile. Idempotente: la prima chiamata
  /// inizializza e chiede i permessi, le successive non fanno nulla.
  Future<bool> ensureInitialized() async {
    if (_ready) return true;
    try {
      tz_data.initializeTimeZones();
      final localZone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(localZone.identifier));

      await plugin.initialize(
        settings: const InitializationSettings(
          // Silhouette monocroma: in barra di stato Android appiattisce
          // l'icona sul canale alfa, quindi ic_launcher (quadrato opaco a
          // colori) diventerebbe un rettangolo bianco pieno.
          android: AndroidInitializationSettings(kAndroidNotificationIcon),
          iOS: DarwinInitializationSettings(
            // I permessi si chiedono all'avvio della prima sessione, non
            // all'apertura dell'app: il consenso arriva quando il motivo è
            // evidente all'utente.
            requestAlertPermission: true,
            requestSoundPermission: true,
            requestBadgePermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: _publishResponse,
        onDidReceiveBackgroundNotificationResponse: onBackgroundResponse,
      );

      final android = plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await android?.requestNotificationsPermission();
      await android?.requestExactAlarmsPermission();

      _ready = true;
    } catch (error, stackTrace) {
      reportNotificationError('inizializzazione notifiche', error, stackTrace);
    }
    return _ready;
  }

  void _publishResponse(NotificationResponse response) {
    if (!_responses.isClosed) _responses.add(response);
  }

  Future<void> dispose() => _responses.close();
}

/// Errori di piattaforma delle notifiche: si segnalano, non si propagano.
/// Una notifica mancata non deve interrompere l'allenamento.
void reportNotificationError(String what, Object error, StackTrace stackTrace) {
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: error,
      stack: stackTrace,
      library: 'notifications',
      context: ErrorDescription(what),
    ),
  );
}
