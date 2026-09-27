import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tacca/services/notifications/notification_host.dart';

/// L'icona delle notifiche la nomina solo il codice Dart: nella release lo
/// shrinking delle risorse la toglie se `keep.xml` non la trattiene, e il
/// plugin smette di inizializzarsi senza che niente fallisca in debug. Questo
/// test è l'unico posto in cui la dimenticanza si vede prima del device.
void main() {
  final name = kAndroidNotificationIcon.replaceFirst('@drawable/', '');

  test('l\'icona delle notifiche è una drawable che esiste', () {
    expect(kAndroidNotificationIcon, startsWith('@drawable/'));
    final found = Directory('android/app/src/main/res')
        .listSync()
        .whereType<Directory>()
        .where((dir) => dir.path.split('/').last.startsWith('drawable'))
        .any(
          (dir) => dir.listSync().any(
            (file) => file.path.split('/').last.split('.').first == name,
          ),
        );
    expect(found, isTrue, reason: 'manca la drawable $name');
  });

  test('keep.xml trattiene l\'icona delle notifiche nella release', () {
    final keep = File('android/app/src/main/res/raw/keep.xml');
    expect(keep.existsSync(), isTrue);
    final match = RegExp(
      r'tools:keep="([^"]*)"',
    ).firstMatch(keep.readAsStringSync());
    expect(match, isNotNull, reason: 'keep.xml senza tools:keep');
    final kept = match!.group(1)!.split(',').map((entry) => entry.trim());
    expect(kept, contains(kAndroidNotificationIcon));
  });
}
