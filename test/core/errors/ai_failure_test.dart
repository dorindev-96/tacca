import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tacca/core/errors/ai_exception.dart';
import 'package:tacca/core/errors/ai_failure.dart';
import 'package:tacca/l10n/app_localizations.dart';

void main() {
  group('AiFailure.from', () {
    test('ogni sottotipo di AiException ha il suo fallimento', () {
      expect(AiFailure.from(const AiAuthException('x')), AiFailure.auth);
      expect(AiFailure.from(const AiQuotaException('x')), AiFailure.quota);
      expect(AiFailure.from(const AiNetworkException('x')), AiFailure.network);
      expect(
        AiFailure.from(const AiResponseException('x')),
        AiFailure.response,
      );
      expect(
        AiFailure.from(const AiConfigurationException('x')),
        AiFailure.notConfigured,
      );
    });

    test('il resto è inatteso, anche la base AiException', () {
      expect(AiFailure.from(const AiException('x')), AiFailure.unexpected);
      expect(AiFailure.from(StateError('boom')), AiFailure.unexpected);
    });
  });

  test('ogni fallimento ha un messaggio in ogni lingua, senza la diagnostica '
      'del provider', () {
    for (final locale in AppLocalizations.supportedLocales) {
      final l10n = lookupAppLocalizations(locale);
      for (final failure in AiFailure.values) {
        final message = failure.message(l10n);
        expect(message, isNotEmpty, reason: '$failure in $locale');
        expect(message, isNot(contains('HTTP')), reason: '$failure, $locale');
      }
    }
  });

  test('i messaggi sono tradotti, non ricadono sull\'italiano', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    for (final failure in AiFailure.values) {
      expect(failure.message(en), isNot(failure.message(it)));
    }
  });
}
