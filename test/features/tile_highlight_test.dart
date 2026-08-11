import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/features/common/tile_highlight.dart';

/// The selected episode's colour appeared over the description above the list.
///
/// The band is drawn *beneath* the description's text, and a Material's ink
/// layer is the only thing that paints there - which is what ListTile's
/// tileColor uses. TileHighlight paints the row's own colour instead, with an
/// ordinary render object the viewport clips.
///
/// Honest limit: the leak does not reproduce under `flutter test` - not at any
/// scroll offset, nor with a TabBarView, a Stack, or a transparent header, all
/// of which were tried. Widget tests also do not run Impeller, which the device
/// does. So these assert the invariant and the absence of regressions; the
/// device is the only place the original artifact has ever been seen.
void main() {
  const highlight = Color(0xFFAA0055);
  const boundaryKey = ValueKey('boundary');

  Widget harness() => MaterialApp(
        home: Scaffold(
          body: RepaintBoundary(
            key: boundaryKey,
            child: Column(children: [
              const SizedBox(height: 120, width: double.infinity),
              Expanded(
                child: ListView.builder(
                  itemCount: 40,
                  itemExtent: 56,
                  itemBuilder: (context, i) => TileHighlight(
                    highlighted: i == 2,
                    color: highlight,
                    child: ListTile(title: Text('row $i'), onTap: () {}),
                  ),
                ),
              ),
            ]),
          ),
        ),
      );

  Future<int> highlightPixelsAbove(WidgetTester tester, double y) async {
    final boundary =
        tester.renderObject<RenderRepaintBoundary>(find.byKey(boundaryKey));
    final image = await tester.runAsync(() => boundary.toImage());
    final data = await tester
        .runAsync(() => image!.toByteData(format: ui.ImageByteFormat.rawRgba));
    final bytes = data!.buffer.asUint8List();
    final width = image!.width;
    var hits = 0;
    for (var row = 0; row < y.round(); row++) {
      for (var x = 0; x < width; x++) {
        final i = (row * width + x) * 4;
        if (Color.fromARGB(
                bytes[i + 3], bytes[i], bytes[i + 1], bytes[i + 2]) ==
            highlight) {
          hits++;
        }
      }
    }
    return hits;
  }

  testWidgets('the highlight never paints above its list', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    for (final dy in [-30.0, -100.0, -200.0, -600.0]) {
      await tester.drag(find.byType(ListView), Offset(0, dy));
      await tester.pumpAndSettle();
      expect(await highlightPixelsAbove(tester, 120), 0,
          reason: 'leaked above the list after scrolling $dy');
    }
  });

  testWidgets('the highlight still paints on its own row', (tester) async {
    // Guards against passing the test above by drawing nothing at all.
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    final boundary =
        tester.renderObject<RenderRepaintBoundary>(find.byKey(boundaryKey));
    final image = await tester.runAsync(() => boundary.toImage());
    final data = await tester
        .runAsync(() => image!.toByteData(format: ui.ImageByteFormat.rawRgba));
    final bytes = data!.buffer.asUint8List();
    var hits = 0;
    for (var i = 0; i < bytes.length; i += 4) {
      if (Color.fromARGB(bytes[i + 3], bytes[i], bytes[i + 1], bytes[i + 2]) ==
          highlight) {
        hits++;
      }
    }
    expect(hits, greaterThan(0), reason: 'the selected row lost its colour');
  });

  testWidgets('an unhighlighted row is left alone', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: TileHighlight(
          highlighted: false, color: highlight, child: Text('plain')),
    ));
    expect(
      find.descendant(
          of: find.byType(TileHighlight), matching: find.byType(ColoredBox)),
      findsNothing,
    );
  });
}
