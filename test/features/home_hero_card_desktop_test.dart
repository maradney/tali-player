import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/features/home/home_hero_card.dart';
import 'package:iptv_player/l10n/app_localizations.dart';

/// The hero card on desktop, across the widths and text scales Windows can
/// actually produce.
///
/// A note on what "Windows display scaling at 125%" does, because the original
/// bug report - mine - assumed wrongly. Flutter lays out in logical pixels, so
/// raising the display scale does **not** enlarge text or change any layout
/// arithmetic: it raises devicePixelRatio, which affects rasterisation only,
/// and shrinks the window's *logical* size for a fixed physical one. So the
/// desktop reproduction is not "125% scaling", it is "a narrower card".
///
/// Windows does have a separate system text-size setting, and that one really
/// does reach Flutter as a textScaler - which is the axis the phone-shaped
/// tests in home_hero_card_growth_test.dart already cover at 1.5.
///
/// What neither file covered is the two together across desktop widths, so
/// this sweeps them. The dashboard caps content at 1280, and the card takes
/// 16pt padding either side.
void main() {
  Widget wrap(Widget child, {required double width, required double scale}) =>
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
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
        progress: 0.35,
        posterUrl: null,
        onResume: () {},
      );

  /// Long enough to wrap at any width the card actually gets.
  const longTitle =
      'The Lord of the Rings: The Fellowship of the Ring - Extended Edition '
      '(2001) Remastered';

  testWidgets('the resume button stays inside the card at every desktop size',
      (tester) async {
    // A restored window, a half-screen split, and the 1280 content cap.
    const widths = [520.0, 700.0, 960.0, 1100.0, 1248.0];
    // 1.0 is the default; Windows' text-size setting reaches 2.25 at its top.
    const scales = [1.0, 1.3, 1.5, 2.0];

    for (final width in widths) {
      for (final scale in scales) {
        tester.view.devicePixelRatio = 1.25; // a 125%-scaled display
        await tester.pumpWidget(
            wrap(card(longTitle), width: width, scale: scale));
        await tester.pumpAndSettle();

        final cardRect = tester.getRect(find.byType(HomeHeroCard));
        final buttonRect = tester.getRect(find.byType(FilledButton));

        expect(buttonRect.bottom, lessThanOrEqualTo(cardRect.bottom),
            reason: 'clipped at width=$width scale=$scale: '
                'card=$cardRect button=$buttonRect');
        expect(tester.takeException(), isNull,
            reason: 'overflow at width=$width scale=$scale');
      }
    }
    addTearDown(tester.view.resetDevicePixelRatio);
  });

  testWidgets('a wide card with a short title keeps its 180 minimum',
      (tester) async {
    // Growing is meant to be the exception. If the card grew on desktop for
    // ordinary content it would dominate the dashboard.
    await tester.pumpWidget(wrap(card('Bleach'), width: 1248, scale: 1.0));
    await tester.pumpAndSettle();

    expect(tester.getRect(find.byType(HomeHeroCard)).height, 180 + 8);
  });
}
