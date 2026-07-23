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
