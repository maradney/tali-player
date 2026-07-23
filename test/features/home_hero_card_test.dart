import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/features/home/home_hero_card.dart';
import 'package:iptv_player/l10n/app_localizations.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      );

  testWidgets('renders eyebrow/title/subtitle and fires onResume',
      (tester) async {
    var resumed = 0;
    await tester.pumpWidget(host(HomeHeroCard(
      eyebrow: 'Continue watching',
      title: 'Dark',
      subtitle: 'S1 · E3',
      posterUrl: null, // fallback thumb — no network in tests
      progress: 0.4,
      onResume: () => resumed++,
    )));
    await tester.pump();

    expect(find.text('CONTINUE WATCHING'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('S1 · E3'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    await tester.tap(find.text('Resume'));
    expect(resumed, 1);

    // The whole banner is tappable, not just the button.
    await tester.tap(find.text('Dark'));
    expect(resumed, 2);
  });

  testWidgets('omits subtitle and progress when absent', (tester) async {
    await tester.pumpWidget(host(HomeHeroCard(
      eyebrow: 'Continue watching',
      title: 'The Matrix',
      onResume: () {},
    )));
    await tester.pump();

    expect(find.text('The Matrix'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
