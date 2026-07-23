import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/api/xtream_api_service.dart';
import 'package:iptv_player/data/sources/m3u_media_source.dart';
import 'package:iptv_player/features/common/api_error_helper.dart';
import 'package:iptv_player/l10n/app_localizations.dart';

import '../support/test_support.dart';

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final account = accountNamed('err-map');

  test('maps each tagged exception kind to its localized message', () {
    String msg(XtreamApiErrorKind kind) => describeApiError(
        XtreamApiException('raw english detail', kind: kind), account, en);

    expect(msg(XtreamApiErrorKind.invalidCredentials),
        en.errInvalidCredentials);
    expect(msg(XtreamApiErrorKind.notXtreamPanel), en.errNotXtreamPanel);
    expect(msg(XtreamApiErrorKind.badResponse), en.errBadResponse);
    expect(msg(XtreamApiErrorKind.timeout), en.errTimeout);
    expect(msg(XtreamApiErrorKind.unreachable), en.errUnreachable);
    expect(msg(XtreamApiErrorKind.rateLimited), en.errRateLimited);
    expect(msg(XtreamApiErrorKind.unavailable), en.errUnavailable);
  });

  test('kind "other" keeps the exception\'s own detail message', () {
    expect(
      describeApiError(
          XtreamApiException('Request failed: boom'), account, en),
      'Request failed: boom',
    );
  });

  test('localizes into the active locale, not hardcoded English', () {
    final ar = lookupAppLocalizations(const Locale('ar'));
    final msg = describeApiError(
        XtreamApiException('x', kind: XtreamApiErrorKind.timeout),
        account,
        ar);
    expect(msg, ar.errTimeout);
    expect(msg, isNot(en.errTimeout));
  });

  test('maps an M3U validation failure', () {
    expect(describeApiError(M3uException('none'), account, en),
        en.errNoChannelsInPlaylist);
  });

  test('falls back to toString for unknown errors', () {
    expect(describeApiError(StateError('odd'), account, en),
        contains('odd'));
  });
}
