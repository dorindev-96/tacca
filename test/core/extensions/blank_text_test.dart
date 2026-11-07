import 'package:flutter_test/flutter_test.dart';
import 'package:tacca/core/extensions/blank_text.dart';

void main() {
  group('BlankText', () {
    test('null, vuoto e soli spazi contano come assenti', () {
      for (final value in [null, '', '   ', '\n\t ']) {
        expect(value.isBlank, isTrue, reason: '"$value"');
        expect(value.trimmedOrNull, isNull, reason: '"$value"');
      }
    });

    test('un testo vero torna senza gli spazi ai bordi', () {
      const value = '  Panca piana \n';
      expect(value.isBlank, isFalse);
      expect(value.trimmedOrNull, 'Panca piana');
    });
  });
}
