import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tacca/data/repositories/settings_repository.dart';
import 'package:tacca/features/settings/cubit/theme_mode_cubit.dart';

import '../../../support/fakes.dart';

class _ThrowingSettings extends FakeSettingsRepository {
  @override
  Future<String?> getThemeModeName() async => throw Exception('keychain');

  @override
  Future<void> setThemeModeName(String? name) async =>
      throw Exception('keychain');
}

void main() {
  test('senza preferenza salvata resta system: decide il telefono', () async {
    final cubit = ThemeModeCubit(settings: FakeSettingsRepository());
    await pumpEventQueue();

    expect(cubit.state, ThemeMode.system);
  });

  test('una preferenza salvata diventa il tema dell\'app', () async {
    final cubit = ThemeModeCubit(
      settings: FakeSettingsRepository(themeModeName: 'dark'),
    );
    await pumpEventQueue();

    expect(cubit.state, ThemeMode.dark);
  });

  test('select fissa il tema e lo salva', () async {
    final settings = FakeSettingsRepository();
    final cubit = ThemeModeCubit(settings: settings);
    await pumpEventQueue();

    await cubit.select(ThemeMode.dark);

    expect(cubit.state, ThemeMode.dark);
    expect(settings.themeModeName, 'dark');
  });

  test('select(system) torna a seguire il telefono e cancella la '
      'preferenza', () async {
    final settings = FakeSettingsRepository(themeModeName: 'light');
    final cubit = ThemeModeCubit(settings: settings);
    await pumpEventQueue();
    expect(cubit.state, ThemeMode.light);

    await cubit.select(ThemeMode.system);

    expect(cubit.state, ThemeMode.system);
    // Non la stringa "system": "mai scelto" è l'assenza della chiave, così
    // rileggerla non dipende da quale nome ci avevamo scritto.
    expect(settings.themeModeName, isNull);
  });

  test(
    'uno storage illeggibile vale "come il sistema", non un crash',
    () async {
      final cubit = ThemeModeCubit(settings: _ThrowingSettings());
      await pumpEventQueue();

      expect(cubit.state, ThemeMode.system);
    },
  );

  test('se il salvataggio fallisce il tema cambia lo stesso: si perde la '
      'preferenza, non il gesto', () async {
    final SettingsRepository settings = _ThrowingSettings();
    final cubit = ThemeModeCubit(settings: settings);
    await pumpEventQueue();

    await cubit.select(ThemeMode.dark);

    expect(cubit.state, ThemeMode.dark);
  });

  test(
    'un valore salvato che non sappiamo leggere vale "mai scelto"',
    () async {
      // Storage manomesso, o scritto da una versione che aggiunge un modo in
      // più: l'avvio non deve esplodere per una preferenza.
      final cubit = ThemeModeCubit(
        settings: FakeSettingsRepository(themeModeName: 'sepia'),
      );
      await pumpEventQueue();

      expect(cubit.state, ThemeMode.system);
      expect(ThemeModeCubit.parse('sepia'), isNull);
      expect(ThemeModeCubit.parse('dark'), ThemeMode.dark);
    },
  );
}
