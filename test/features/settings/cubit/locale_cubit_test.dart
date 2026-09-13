import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tacca/data/repositories/settings_repository.dart';
import 'package:tacca/features/settings/cubit/locale_cubit.dart';

import '../../../support/fakes.dart';

class _ThrowingSettings extends FakeSettingsRepository {
  @override
  Future<String?> getLocaleCode() async => throw Exception('keychain');

  @override
  Future<void> setLocaleCode(String? languageCode) async =>
      throw Exception('keychain');
}

void main() {
  test('senza preferenza salvata resta null: decide il sistema', () async {
    final cubit = LocaleCubit(settings: FakeSettingsRepository());
    await pumpEventQueue();

    expect(cubit.state, isNull);
  });

  test('una preferenza salvata diventa la lingua dell\'app', () async {
    final cubit = LocaleCubit(
      settings: FakeSettingsRepository(localeCode: 'sv'),
    );
    await pumpEventQueue();

    expect(cubit.state, const Locale('sv'));
  });

  test('select fissa la lingua e la salva', () async {
    final settings = FakeSettingsRepository();
    final cubit = LocaleCubit(settings: settings);
    await pumpEventQueue();

    await cubit.select(const Locale('de'));

    expect(cubit.state, const Locale('de'));
    expect(settings.localeCode, 'de');
  });

  test(
    'select(null) torna a seguire il sistema e cancella la preferenza',
    () async {
      final settings = FakeSettingsRepository(localeCode: 'fr');
      final cubit = LocaleCubit(settings: settings);
      await pumpEventQueue();
      expect(cubit.state, const Locale('fr'));

      await cubit.select(null);

      expect(cubit.state, isNull);
      expect(settings.localeCode, isNull);
    },
  );

  test(
    'uno storage illeggibile vale "come il sistema", non un crash',
    () async {
      final cubit = LocaleCubit(settings: _ThrowingSettings());
      await pumpEventQueue();

      expect(cubit.state, isNull);
    },
  );

  test('se il salvataggio fallisce la lingua cambia lo stesso: si perde la '
      'preferenza, non il gesto', () async {
    final SettingsRepository settings = _ThrowingSettings();
    final cubit = LocaleCubit(settings: settings);
    await pumpEventQueue();

    await cubit.select(const Locale('es'));

    expect(cubit.state, const Locale('es'));
  });
}
