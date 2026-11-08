import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tacca/services/share/shared_text_receiver.dart';

/// Il viaggio di ritorno dell'import senza key vive in dichiarazioni native
/// che nessun test Dart esercita e che la CI non compila: l'`intent-filter`
/// e il `launchMode` del manifest, lo schema URL dell'app iOS, la regola di
/// attivazione dell'estensione. Qui si controlla almeno che ci siano, e che
/// i nomi che il Dart e il nativo devono condividere coincidano.
void main() {
  group('Android', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    test('MainActivity riceve i testi condivisi', () {
      expect(manifest, contains('android.intent.action.SEND'));
      expect(manifest, contains('android:mimeType="text/plain"'));
    });

    test('MainActivity è singleTask: una condivisione da un\'altra app non '
        'deve creare un secondo motore Flutter nello stesso processo', () {
      expect(manifest, contains('android:launchMode="singleTask"'));
      expect(manifest, isNot(contains('android:launchMode="singleTop"')));
    });

    test('il canale ha lo stesso nome nel Dart e in MainActivity', () {
      final activity = File(
        'android/app/src/main/kotlin/com/tverdohleb/tacca/MainActivity.kt',
      ).readAsStringSync();
      expect(activity, contains('"${PlatformSharedTextReceiver.channelName}"'));
      expect(activity, contains('"takePending"'));
    });
  });

  group('iOS', () {
    test('l\'app dichiara lo schema con cui l\'estensione la riapre, e non '
        'lo passa al router', () {
      final plist = File('ios/Runner/Info.plist').readAsStringSync();
      expect(plist, contains('<string>tacca</string>'));
      expect(
        plist,
        contains('<key>FlutterDeepLinkingEnabled</key>\n\t<false/>'),
      );
      final controller = File(
        'ios/TaccaShare/ShareViewController.swift',
      ).readAsStringSync();
      expect(controller, contains('"tacca://shared-text"'));
    });

    test('l\'estensione accetta solo testo', () {
      final plist = File('ios/TaccaShare/Info.plist').readAsStringSync();
      expect(plist, contains('com.apple.share-services'));
      expect(plist, contains('NSExtensionActivationSupportsText'));
      expect(plist, isNot(contains('NSExtensionActivationSupportsImage')));
    });

    test('il canale ha lo stesso nome nel Dart e nel ponte Swift', () {
      final bridge = File(
        'ios/Runner/SharedTextBridge.swift',
      ).readAsStringSync();
      expect(bridge, contains('"${PlatformSharedTextReceiver.channelName}"'));
      expect(bridge, contains('"takePending"'));
    });

    test('app ed estensione condividono lo stesso App Group', () {
      final store = File(
        'ios/SharedText/SharedTextStore.swift',
      ).readAsStringSync();
      final group = RegExp(
        r'appGroupId = "([^"]+)"',
      ).firstMatch(store)!.group(1)!;
      for (final path in [
        'ios/Runner/Runner.entitlements',
        'ios/TaccaShare/TaccaShare.entitlements',
        'ios/LiveSessionShared/TaccaSessionAttributes.swift',
      ]) {
        expect(File(path).readAsStringSync(), contains(group), reason: path);
      }
    });

    test('il progetto Xcode compila lo store in entrambi i target', () {
      final project = File(
        'ios/Runner.xcodeproj/project.pbxproj',
      ).readAsStringSync();
      expect(
        project,
        contains('TaccaShare.appex in Embed Foundation Extensions'),
      );
      expect(
        RegExp(r'SharedTextStore\.swift in Sources \*/,').allMatches(project),
        hasLength(2),
      );
    });
  });
}
