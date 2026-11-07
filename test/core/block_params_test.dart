import 'package:flutter_test/flutter_test.dart';
import 'package:tacca/core/block_params.dart';
import 'package:tacca/data/entities/block.dart';
import 'package:tacca/l10n/app_localizations_it.dart';

void main() {
  final l10n = AppLocalizationsIt();

  group('BlockParam', () {
    test('ogni parametro scrive e rilegge il proprio campo, e solo quello', () {
      for (final param in BlockParam.values) {
        final block = Block.ofType(BlockType.standard);
        param.write(block, 42);

        for (final other in BlockParam.values) {
          expect(
            other.read(block),
            other == param ? 42 : isNull,
            reason: '$param scritto, $other letto',
          );
        }
      }
    });

    test('ogni parametro appartiene ad almeno un tipo', () {
      final used = {
        for (final type in BlockType.values) ...BlockParam.of(type),
      };
      expect(used, BlockParam.values.toSet());
    });

    test('i default sono quelli di sempre (§5.2)', () {
      Map<BlockParam, int?> defaults(BlockType type) => {
        for (final param in BlockParam.of(type)) param: param.defaultFor(type),
      };

      expect(defaults(BlockType.standard), isEmpty);
      expect(defaults(BlockType.freeText), isEmpty);
      expect(defaults(BlockType.superset), {
        BlockParam.rounds: 3,
        BlockParam.restBetweenRounds: 60,
      });
      expect(defaults(BlockType.circuit), defaults(BlockType.superset));
      expect(defaults(BlockType.emom), {
        BlockParam.interval: 60,
        BlockParam.totalMinutes: 10,
      });
      expect(defaults(BlockType.amrap), {BlockParam.duration: 900});
      expect(defaults(BlockType.tabata), {
        BlockParam.work: 20,
        BlockParam.rest: 10,
        BlockParam.rounds: 8,
      });
      // Il time cap è opzionale: il blocco nasce senza.
      expect(defaults(BlockType.forTime), {BlockParam.timeCap: null});
    });

    test('un parametro fuori dal tipo non ha default', () {
      for (final type in BlockType.values) {
        for (final param in BlockParam.values) {
          if (BlockParam.of(type).contains(param)) continue;
          expect(param.defaultFor(type), isNull, reason: '$param su $type');
        }
      }
    });
  });

  group('blockParamTexts', () {
    test('scrive i parametri del tipo, nel suo ordine, come in sessione', () {
      final tabata = Block.ofType(BlockType.tabata)
        ..workSeconds = 20
        ..restSeconds = 10
        ..rounds = 8;
      expect(blockParamTexts(l10n, tabata), [
        '20s di lavoro',
        '10s di recupero',
        '8 giri',
      ]);

      final superset = Block.ofType(BlockType.superset)
        ..rounds = 1
        ..restBetweenRoundsSeconds = 60;
      expect(blockParamTexts(l10n, superset), ['1 giro', '60s tra i giri']);
    });

    test('salta i parametri assenti, a zero o di un altro tipo', () {
      final emom = Block.ofType(BlockType.emom)
        ..intervalSeconds = 60
        ..totalMinutes = 0
        // Un residuo di un altro tipo non si mostra.
        ..timeCapSeconds = 600;
      expect(blockParamTexts(l10n, emom), ['ogni 60s']);

      expect(blockParamTexts(l10n, Block.ofType(BlockType.forTime)), isEmpty);
    });
  });
}
