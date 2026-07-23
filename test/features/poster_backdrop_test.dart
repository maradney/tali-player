import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/features/common/poster_backdrop.dart';

void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('with no poster it renders just the child', (tester) async {
    await tester.pumpWidget(host(const PosterBackdrop(
      posterUrl: null,
      child: Text('body'),
    )));
    await tester.pump();

    expect(find.text('body'), findsOneWidget);
    expect(find.byType(ImageFiltered), findsNothing);
  });

  testWidgets('with a poster it layers blur + scrim under the child',
      (tester) async {
    await tester.pumpWidget(host(const PosterBackdrop(
      posterUrl: 'http://host/poster.jpg',
      child: Text('body'),
    )));
    await tester.pump();

    expect(find.text('body'), findsOneWidget);
    expect(find.byType(ImageFiltered), findsOneWidget);
    // The backdrop layers must never intercept taps meant for the body.
    expect(
      find.ancestor(
        of: find.byType(ImageFiltered),
        matching: find.byType(IgnorePointer),
      ),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
  });
}
