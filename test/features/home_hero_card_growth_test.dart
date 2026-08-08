import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/features/home/home_hero_card.dart';
import 'package:iptv_player/l10n/app_localizations.dart';

/// The hero card used a fixed 180pt height. A long title wrapping onto its
/// second line - or any text scale above the default - pushed the resume
/// button past the bottom, where the card's ClipRRect cut it off silently
/// rather than reporting an overflow.
void main() {
  Widget wrap(Widget child, {double textScale = 1.0, double width = 411}) =>
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(width: width, child: child),
            ),
          ),
        ),
      );

  Widget card(String title) => HomeHeroCard(
        eyebrow: 'CONTINUE WATCHING',
        title: title,
        subtitle: 'S1 · E1',
        progress: 0.1,
        posterUrl: null,
        onResume: () {},
      );

  // The real title that showed the problem on a phone.
  const longTitle = 'Saga of Tanya the Evil (ANM 2017-2026)';
  const shortTitle = 'Bleach';

  testWidgets('keeps the resume button on screen with a long title',
      (tester) async {
    await tester.pumpWidget(wrap(card(longTitle)));
    await tester.pumpAndSettle();

    final button = find.byType(FilledButton);
    expect(button, findsOneWidget);

    // The button must sit inside the card, not past its bottom edge.
    final cardRect = tester.getRect(find.byType(HomeHeroCard));
    final buttonRect = tester.getRect(button);
    expect(buttonRect.bottom, lessThanOrEqualTo(cardRect.bottom),
        reason: 'resume button clipped: card=$cardRect button=$buttonRect');
    expect(tester.takeException(), isNull);
  });

  testWidgets('grows for a large accessibility text scale', (tester) async {
    await tester.pumpWidget(wrap(card(longTitle), textScale: 1.5));
    await tester.pumpAndSettle();

    final cardRect = tester.getRect(find.byType(HomeHeroCard));
    final buttonRect = tester.getRect(find.byType(FilledButton));
    expect(buttonRect.bottom, lessThanOrEqualTo(cardRect.bottom));
    expect(cardRect.height, greaterThan(180),
        reason: 'card should have grown past its old fixed height');
    expect(tester.takeException(), isNull);
  });

  testWidgets('still 180 tall for an ordinary short title', (tester) async {
    // The minimum is what gives the card its presence on the dashboard;
    // growing must be the exception, not the rule.
    await tester.pumpWidget(wrap(card(shortTitle)));
    await tester.pumpAndSettle();

    expect(tester.getRect(find.byType(HomeHeroCard)).height, 180 + 8);
    expect(tester.takeException(), isNull);
  });
}
