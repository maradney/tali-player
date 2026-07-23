import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/models/search_result.dart';
import 'package:iptv_player/data/services/home_strips_service.dart';
import 'package:iptv_player/features/home/home_strips_editor.dart';
import 'package:iptv_player/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/test_support.dart';

void main() {
  final service = HomeStripsService.instance;
  final account = accountNamed('strips-editor');

  Widget host() => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: HomeStripsEditor(
            account: account,
            availableTypes: const {
              ContentType.live,
              ContentType.movie,
              ContentType.series,
            },
          ),
        ),
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await service.deleteFor(account);
    await service.loadFor(account);
  });

  testWidgets('lists every strip with a switch, in order', (tester) async {
    await tester.pumpWidget(host());
    final l = lookupAppLocalizations(const Locale('en'));

    expect(find.text(l.continueWatching), findsOneWidget);
    expect(find.text(l.watchlistTitle), findsOneWidget);
    expect(find.text(l.recentlyAddedTitle), findsOneWidget);
    expect(find.text(l.downloadsTitle), findsOneWidget);
    expect(find.text(l.favoritesTitle), findsOneWidget);
    expect(find.byType(Switch), findsNWidgets(5));
    expect(find.text(l.addCategoryRail), findsOneWidget);
  });

  testWidgets('flipping a switch disables that strip', (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    expect(service.strips.first.enabled, isFalse);
    expect(service.enabledStrips, hasLength(4));
  });

  testWidgets('a category strip shows a delete button that removes it',
      (tester) async {
    await service.addCategory(
        type: ContentType.movie, categoryId: '42', categoryName: '4K Movies');
    await tester.pumpWidget(host());

    expect(find.text('4K Movies'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(find.text('4K Movies'), findsNothing);
    expect(service.strips.where((s) => s.categoryId == '42'), isEmpty);
  });
}
