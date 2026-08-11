import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/features/common/expandable_text.dart';
import 'package:iptv_player/l10n/app_localizations.dart';

/// A series plot was clamped to four lines ending in "..." with no way to read
/// the rest, which on a phone is most of them.
void main() {
  Widget wrap(String text, {double width = 380, double textScale = 1.0}) =>
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: width,
                child: ExpandableText(text: text, collapsedLines: 4),
              ),
            ),
          ),
        ),
      );

  final long = List.filled(80, 'lorem ipsum dolor').join(' ');
  const short = 'A short plot.';

  testWidgets('long text offers a way to read the rest', (tester) async {
    await tester.pumpWidget(wrap(long));
    await tester.pumpAndSettle();

    expect(find.text('Show more'), findsOneWidget);
    final collapsed = tester.getSize(find.byType(ExpandableText)).height;

    await tester.tap(find.text('Show more'));
    await tester.pumpAndSettle();

    expect(find.text('Show less'), findsOneWidget);
    expect(tester.getSize(find.byType(ExpandableText)).height,
        greaterThan(collapsed));
    expect(tester.takeException(), isNull);
  });

  testWidgets('collapses again', (tester) async {
    await tester.pumpWidget(wrap(long));
    await tester.pumpAndSettle();
    final collapsed = tester.getSize(find.byType(ExpandableText)).height;

    await tester.tap(find.text('Show more'));
    await tester.pumpAndSettle();
    // Expanded, the toggle is pushed below the viewport - scroll it back into
    // reach or the tap lands on nothing and the test passes for the wrong
    // reason.
    await tester.ensureVisible(find.text('Show less'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show less'));
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(ExpandableText)).height, collapsed);
  });

  testWidgets('short text shows no toggle at all', (tester) async {
    // The affordance has to be absent, not merely inert - a "More" button that
    // does nothing is worse than no button.
    await tester.pumpWidget(wrap(short));
    await tester.pumpAndSettle();

    expect(find.text('Show more'), findsNothing);
    expect(find.text('Show less'), findsNothing);
  });

  testWidgets('fit is measured, not guessed from length', (tester) async {
    // The same string overflows at one width and not another; a character
    // count would get this wrong in both directions.
    const medium = 'Just enough words here to wrap onto about two lines total.';
    await tester.pumpWidget(wrap(medium, width: 600));
    await tester.pumpAndSettle();
    expect(find.text('Show more'), findsNothing);

    await tester.pumpWidget(wrap(medium, width: 90));
    await tester.pumpAndSettle();
    expect(find.text('Show more'), findsOneWidget,
        reason: 'narrow enough that the same text now needs >4 lines');
  });

  testWidgets('a large text scale can bring the toggle in', (tester) async {
    const medium = 'Just enough words here to wrap onto about three lines.';
    await tester.pumpWidget(wrap(medium, width: 300));
    await tester.pumpAndSettle();
    final atDefault = find.text('Show more').evaluate().length;

    await tester.pumpWidget(wrap(medium, width: 300, textScale: 2.5));
    await tester.pumpAndSettle();
    expect(find.text('Show more'), findsOneWidget,
        reason: 'accessibility scaling pushes it past four lines');
    expect(atDefault, 0);
  });
}
