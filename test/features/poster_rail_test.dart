import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/features/common/poster_rail.dart';
import 'package:iptv_player/l10n/app_localizations.dart';

/// Pumps a single-item `PosterRail<String>` with the given callbacks, wrapped in
/// the l10n delegates it needs. Returns nothing — the test drives it via finders.
Future<void> _pumpRail(
  WidgetTester tester, {
  bool inWatchlist = false,
  bool locked = false,
  void Function(String)? onToggleWatchlist,
  void Function(String)? onLongPress,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: PosterRail<String>(
          title: 'Recently added',
          items: const ['movie-1'],
          titleOf: (s) => s,
          posterUrlOf: (_) => null,
          onTap: (_) {},
          isLocked: (_) => locked,
          isInWatchlist: onToggleWatchlist == null ? null : (_) => inWatchlist,
          onToggleWatchlist: onToggleWatchlist,
          onLongPress: onLongPress,
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('shows an outline bookmark when the item is not in the watchlist',
      (tester) async {
    await _pumpRail(tester, inWatchlist: false, onToggleWatchlist: (_) {});
    expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
    expect(find.byIcon(Icons.bookmark), findsNothing);
  });

  testWidgets('shows a filled bookmark when the item is in the watchlist',
      (tester) async {
    await _pumpRail(tester, inWatchlist: true, onToggleWatchlist: (_) {});
    expect(find.byIcon(Icons.bookmark), findsOneWidget);
    expect(find.byIcon(Icons.bookmark_border), findsNothing);
  });

  testWidgets('no bookmark at all when no watch-later callback is given',
      (tester) async {
    await _pumpRail(tester); // onToggleWatchlist null
    expect(find.byIcon(Icons.bookmark_border), findsNothing);
    expect(find.byIcon(Icons.bookmark), findsNothing);
  });

  testWidgets('tapping the bookmark fires the watch-later toggle',
      (tester) async {
    String? toggled;
    await _pumpRail(tester, onToggleWatchlist: (s) => toggled = s);
    await tester.tap(find.byIcon(Icons.bookmark_border));
    expect(toggled, 'movie-1');
  });

  testWidgets('long-pressing the tile fires the lock handler', (tester) async {
    String? longPressed;
    await _pumpRail(tester, onLongPress: (s) => longPressed = s);
    // The chevron IconButtons carry InkWells too — long-press the tile itself.
    await tester.longPress(find.text('movie-1'));
    expect(longPressed, 'movie-1');
  });

  testWidgets('a locked tile shows the lock overlay', (tester) async {
    await _pumpRail(tester, locked: true, onToggleWatchlist: (_) {});
    expect(find.byIcon(Icons.lock), findsOneWidget);
  });

  group('desktop affordances', () {
    Widget manyItemRail({int count = 20}) => MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: PosterRail<String>(
              title: 'Rail',
              items: [for (var i = 0; i < count; i++) 'Item $i'],
              titleOf: (s) => s,
              posterUrlOf: (_) => null,
              onTap: (_) {},
            ),
          ),
        );

    ScrollableState railScrollable(WidgetTester tester) =>
        tester.state<ScrollableState>(find.descendant(
          of: find.byType(PosterRail<String>),
          matching: find.byType(Scrollable),
        ));

    AnimatedOpacity chevronOpacity(WidgetTester tester, IconData icon) =>
        tester.widget<AnimatedOpacity>(find
            .ancestor(
              of: find.byIcon(icon),
              matching: find.byType(AnimatedOpacity),
            )
            .first);

    testWidgets('mouse wheel scrolls the rail horizontally', (tester) async {
      await tester.pumpWidget(manyItemRail());
      await tester.pump();

      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      pointer.hover(tester.getCenter(find.text('Item 1')));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 120)));
      await tester.pump();

      expect(railScrollable(tester).position.pixels, 120);
    });

    testWidgets('chevrons appear on hover and page the rail', (tester) async {
      await tester.pumpWidget(manyItemRail());
      await tester.pump();

      // Not hovering: the forward chevron exists but is fully transparent.
      expect(chevronOpacity(tester, Icons.chevron_right).opacity, 0);

      final gesture =
          await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.text('Item 1')));
      await tester.pump();

      expect(chevronOpacity(tester, Icons.chevron_right).opacity, 1);

      await tester.tap(find.byIcon(Icons.chevron_right),
          warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(railScrollable(tester).position.pixels, greaterThan(0));

      // Scrolled away from the start, the back chevron pages home again.
      await tester.tap(find.byIcon(Icons.chevron_left), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(railScrollable(tester).position.pixels, 0);
    });

    testWidgets('a rail that fits ignores the wheel and shows no affordances',
        (tester) async {
      await tester.pumpWidget(manyItemRail(count: 2));
      await tester.pump();

      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      pointer.hover(tester.getCenter(find.text('Item 1')));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 120)));
      await tester.pump();

      expect(railScrollable(tester).position.pixels, 0);
      for (final o in tester
          .widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity))) {
        expect(o.opacity, 0, reason: 'nothing to scroll toward');
      }
    });
  });
}
