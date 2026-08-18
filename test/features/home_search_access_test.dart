import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/features/common/layout_breakpoints.dart';
import 'package:iptv_player/features/home/home_search_pill.dart';
import 'package:iptv_player/features/home/home_shell.dart';

/// Getting to Search on a phone took two taps and a scan: it is the last of
/// ten destinations, so the bottom bar pushed it into "More", and that same
/// ordering put it at the bottom of the sheet. Two changes, neither of which
/// may touch the desktop layout - the rail already lists Search permanently.
void main() {
  group('More sheet order', () {
    test('Search is pinned first without reordering the rest', () {
      // The overflow a phone actually produces: New, Browse, Favorites,
      // Watchlist, History, Search.
      expect(moreSheetOrder([4, 5, 6, 7, 8, 9]), [9, 4, 5, 6, 7, 8]);
    });

    test('an overflow without Search is left exactly as it was', () {
      // M3U hides Search, so the sheet must not gain or lose anything.
      expect(moreSheetOrder([4, 6, 8]), [4, 6, 8]);
    });

    test('nothing is dropped or duplicated', () {
      const overflow = [4, 5, 6, 7, 8, 9];
      final ordered = moreSheetOrder(overflow);
      expect(ordered.toSet(), overflow.toSet());
      expect(ordered, hasLength(overflow.length));
    });

    test('the bar split is untouched by the pin', () {
      // The pin must reorder the sheet only. If it leaked into destination
      // order, Search would climb into the bottom bar and displace Series.
      final split = splitDestinationsForBar([0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
      expect(split.bar, [0, 1, 2, 3],
          reason: 'the content types must keep the bar');
      expect(split.overflow.first, 4,
          reason: 'destination order itself must be unchanged');
    });
  });

  group('home search pill visibility', () {
    test('shows on phone widths, hidden at desktop widths', () {
      expect(showsHomeSearchPill(411), isTrue, reason: 'portrait phone');
      expect(showsHomeSearchPill(699), isTrue, reason: 'just below breakpoint');
      expect(showsHomeSearchPill(700), isFalse, reason: 'the breakpoint itself');
      expect(showsHomeSearchPill(1280), isFalse, reason: 'desktop window');
      expect(showsHomeSearchPill(1920), isFalse);
    });

    test('agrees with the layout that decides the rail', () {
      // Two truths that must never diverge: if the rail is showing, Search is
      // already permanently visible and the pill would be a duplicate.
      for (var w = 200.0; w <= 2000; w += 1) {
        expect(showsHomeSearchPill(w), !isWideLayout(w), reason: 'w=$w');
      }
    });
  });

  group('home search pill widget', () {
    Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

    testWidgets('shows the hint and fires on tap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(wrap(HomeSearchPill(
        hint: 'Search live TV, movies, series…',
        onTap: () => taps++,
      )));

      expect(find.text('Search live TV, movies, series…'), findsOneWidget);
      expect(find.byIcon(Icons.search), findsOneWidget);

      await tester.tap(find.byType(HomeSearchPill));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });

    testWidgets('is not a text field', (tester) async {
      // Typing belongs to the Search screen, which owns the query and tabs. A
      // real field here would either duplicate that or hand text over midway.
      await tester.pumpWidget(wrap(HomeSearchPill(hint: 'x', onTap: () {})));
      expect(find.byType(EditableText), findsNothing);
    });

    testWidgets('is a button to assistive tech', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(wrap(HomeSearchPill(hint: 'Find', onTap: () {})));

      expect(
        tester.getSemantics(find.descendant(
          of: find.byType(HomeSearchPill),
          matching: find.byType(InkWell),
        )),
        isSemantics(label: 'Find', isButton: true, hasTapAction: true),
      );
      handle.dispose();
    });

    testWidgets('a long hint truncates instead of overflowing', (tester) async {
      // Every locale gets its own translation of this string; German and
      // Portuguese are both markedly longer than the English.
      await tester.pumpWidget(wrap(SizedBox(
        width: 320,
        child: HomeSearchPill(
          hint: 'Durchsuchen Sie Live-Fernsehen, Filme und Serien nach Titel',
          onTap: () {},
        ),
      )));
      expect(tester.takeException(), isNull);
    });
  });
}
