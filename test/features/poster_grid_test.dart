import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/features/common/poster_grid.dart';
import 'package:iptv_player/l10n/app_localizations.dart';

void main() {
  Widget host(Widget child, {double textScale = 1.0}) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(body: child),
        ),
      );

  PosterGrid<String> grid(List<String> items) => PosterGrid<String>(
        items: items,
        titleOf: (s) => s,
        posterUrlOf: (_) => null,
        onTap: (_) {},
      );

  testWidgets('two-line titles fit the tile without overflowing',
      (tester) async {
    // Regression: the title area used to be a hard-coded 34px, which a
    // taller-than-Roboto font overflowed by 4px on any wrapped title.
    await tester.pumpWidget(host(grid([
      'A very long title that definitely wraps onto a second line in a tile',
      'Short',
    ])));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('A very long title'), findsOneWidget);
  });

  testWidgets('survives large system text scaling without overflowing',
      (tester) async {
    // At 1.5x the old fixed 34px reservation was far too small (2 lines of
    // 18px-tall text + 4px gap = 40px) and threw a RenderFlex overflow.
    await tester.pumpWidget(host(
      grid(['A very long title that wraps onto a second line for sure']),
      textScale: 1.5,
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('shows a bookmark toggle when watchlist callbacks are wired',
      (tester) async {
    final toggled = <String>[];
    await tester.pumpWidget(host(PosterGrid<String>(
      items: const ['Dune'],
      titleOf: (s) => s,
      posterUrlOf: (_) => null,
      onTap: (_) {},
      isInWatchlist: (_) => false,
      onToggleWatchlist: toggled.add,
    )));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.bookmark_border));
    expect(toggled, ['Dune']);
  });

  testWidgets('hides the bookmark when watchlist callbacks are absent',
      (tester) async {
    await tester.pumpWidget(host(grid(['Dune'])));
    await tester.pump();

    expect(find.byIcon(Icons.bookmark_border), findsNothing);
    expect(find.byIcon(Icons.bookmark), findsNothing);
  });
}
