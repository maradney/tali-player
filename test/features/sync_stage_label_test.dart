import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/models/search_result.dart';
import 'package:iptv_player/features/common/sync_status_toast.dart';
import 'package:iptv_player/l10n/app_localizations.dart';

void main() {
  test('joins the syncing types with their localized nav names', () {
    final en = lookupAppLocalizations(const Locale('en'));
    expect(
      syncStageLabel(en, [ContentType.live, ContentType.movie]),
      'Live TV, Movies',
    );
    expect(syncStageLabel(en, []), '');
  });

  test('uses the active locale, not hardcoded English', () {
    // Regression: the stage string used to be built inside the service with
    // hardcoded English labels, leaking into the 12 other locales' toasts.
    final ar = lookupAppLocalizations(const Locale('ar'));
    expect(syncStageLabel(ar, [ContentType.series]), ar.navSeries);
    expect(syncStageLabel(ar, [ContentType.series]), isNot('Series'));
  });
}
