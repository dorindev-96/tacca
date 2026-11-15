import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tacca/services/share/text_share_service.dart';

/// Su iOS il testo esce dal nostro ponte nativo e non da share_plus: è ciò
/// che evita l'app congelata dopo una condivisione verso un'estensione che
/// rimanda subito alla sua app (vedi `ios/Runner/TextShareBridge.swift`).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(SystemTextShareService.iosChannelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  void answer(Object? Function(MethodCall call) reply) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return reply(call);
    });
  }

  setUp(() {
    calls.clear();
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });

  for (final (raw, outcome) in [
    ('shared', TextShareOutcome.shared),
    ('dismissed', TextShareOutcome.dismissed),
    ('unavailable', TextShareOutcome.unavailable),
  ]) {
    test('su iOS la risposta "$raw" del ponte diventa $outcome', () async {
      answer((_) => raw);

      final result = await const SystemTextShareService().share(
        'prompt',
        subject: 'Tacca',
        originRect: const Rect.fromLTWH(10, 20, 30, 40),
      );

      expect(result, outcome);
      expect(calls.single.method, 'share');
      expect(calls.single.arguments, {
        'text': 'prompt',
        'subject': 'Tacca',
        'origin': [10.0, 20.0, 30.0, 40.0],
      });
    });
  }

  test('un errore del ponte è un foglio non disponibile: il testo andrà '
      'negli appunti', () async {
    answer((_) => throw PlatformException(code: 'boom'));

    expect(
      await const SystemTextShareService().share('prompt'),
      TextShareOutcome.unavailable,
    );
  });

  test('fuori da iOS il ponte non si tocca', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    answer((_) => 'shared');

    // share_plus non ha piattaforma nei test: risponde "non disponibile".
    await const SystemTextShareService().share('prompt');

    expect(calls, isEmpty);
  });
}
