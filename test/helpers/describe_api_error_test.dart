import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/api/xtream_api_service.dart';
import 'package:iptv_player/features/common/api_error_helper.dart';
import 'package:iptv_player/l10n/app_localizations.dart';

import '../support/test_support.dart';

void main() {
  final account = accountNamed('err');
  late AppLocalizations l;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    l = await AppLocalizations.delegate.load(const Locale('en'));
  });

  test('a plain error is described by its toString', () {
    final message = describeApiError(const FormatException('boom'), account, l);
    expect(message, contains('boom'));
  });

  test('a non-rate-limited API exception passes its own message through', () {
    final message = describeApiError(
        XtreamApiException('Connection timed out.'), account, l);
    expect(message, 'Connection timed out.');
  });

  test('an https-on-a-plain-http-port failure says how to fix it', () {
    // The whole point of this kind: the raw text was
    // "WRONG_VERSION_NUMBER(tls_record.cc:127)", which hides a one-word fix.
    final message = describeApiError(
      XtreamApiException('unused English fallback',
          kind: XtreamApiErrorKind.httpsNotSupported),
      account,
      l,
    );
    expect(message, isNot(contains('WRONG_VERSION_NUMBER')));
    expect(message, contains('http://'));
    expect(message, contains('https://'));
  });

  test('a certificate failure does not tell you to switch to http', () {
    // Downgrading to plain HTTP is not the fix for a bad certificate, and
    // suggesting it would be poor advice.
    final message = describeApiError(
      XtreamApiException('unused English fallback',
          kind: XtreamApiErrorKind.tlsHandshakeFailed),
      account,
      l,
    );
    expect(message, isNot(contains('http://')));
    expect(message.toLowerCase(), contains('secure'));
  });

  test(
      'a rate-limited exception is not specialized while nothing is syncing '
      'for the account', () {
    // The "background sync is eating the request budget" wording only kicks
    // in when a sync is actually running for this account; otherwise the
    // raw message is used.
    final message = describeApiError(
      XtreamApiException('rate limited', isRateLimited: true),
      account,
      l,
    );
    expect(message, 'rate limited');
  });
}
