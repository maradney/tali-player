import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// The "Continue watching" row smeared across the description above the
/// episode list while scrolling - not just its colour, but its text too.
///
/// The cause was a GlobalKey left attached to that one row. ListView recycles
/// children as they leave the viewport, and a GlobalKey turns recycling into
/// element reparenting: the row is deactivated and re-adopted, and can be
/// painted at a stale offset outside the sliver's clip. The key was only ever
/// needed for a single ensureVisible call.
///
/// Checked in pixels, because the widget tree is the same either way.
///
/// Honest limit: a bare GlobalKey on a recycled child does *not* reproduce the
/// leak in this harness - the real screen also nests the list in a TabBarView
/// inside a Stack, and something in that combination is needed. So these are
/// an invariant guard, not a reproduction: they assert the row's paint stays
/// inside its list, and would catch a regression that reintroduced it here.
/// The artifact itself was diagnosed from a screen recording, where the row's
/// "Continue watching" text - not merely its colour - appeared over the
/// description, which is what ruled out every ink-based explanation.
void main() {
  const highlight = Color(0xFFAA0055);
  const headerColor = Color(0xFF101010);
  const headerKey = ValueKey('header');
  const boundaryKey = ValueKey('boundary');

  Widget harness({required bool keepGlobalKey, required GlobalKey rowKey}) {
    return MaterialApp(
      home: Scaffold(
        body: RepaintBoundary(
          key: boundaryKey,
          child: Column(
            children: [
              Container(
                  key: headerKey,
                  height: 200,
                  width: double.infinity,
                  color: headerColor),
              Expanded(
                child: ListView.builder(
                  itemCount: 60,
                  itemExtent: 56,
                  itemBuilder: (context, i) {
                    final selected = i == 2;
                    return Container(
                      key: selected && keepGlobalKey ? rowKey : null,
                      color: selected ? highlight : null,
                      alignment: Alignment.centerLeft,
                      child: Text('row $i'),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Pixels of [highlight] found inside the header, i.e. above the list.
  Future<int> leakedPixels(WidgetTester tester) async {
    final headerRect = tester.getRect(find.byKey(headerKey));
    final boundary =
        tester.renderObject<RenderRepaintBoundary>(find.byKey(boundaryKey));
    final boundaryRect = tester.getRect(find.byKey(boundaryKey));
    final image = await tester.runAsync(() => boundary.toImage());
    final data = await tester
        .runAsync(() => image!.toByteData(format: ui.ImageByteFormat.rawRgba));
    final bytes = data!.buffer.asUint8List();
    final width = image!.width;
    final top = (headerRect.top - boundaryRect.top).round();
    final bottom = (headerRect.bottom - boundaryRect.top).round();
    var hits = 0;
    for (var y = top; y < bottom; y++) {
      for (var x = 0; x < width; x++) {
        final i = (y * width + x) * 4;
        if (Color.fromARGB(
                bytes[i + 3], bytes[i], bytes[i + 1], bytes[i + 2]) ==
            highlight) {
          hits++;
        }
      }
    }
    return hits;
  }

  /// Drives the row out of the viewport and back, several times - the row has
  /// to be recycled for the reparenting to happen at all.
  Future<void> scrubTheList(WidgetTester tester) async {
    await tester.pumpAndSettle();
    for (var i = 0; i < 4; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, 400));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('without a lingering GlobalKey the row stays in its list',
      (tester) async {
    final rowKey = GlobalKey();
    await tester.pumpWidget(harness(keepGlobalKey: false, rowKey: rowKey));
    await scrubTheList(tester);
    expect(await leakedPixels(tester), 0,
        reason: 'the highlighted row painted above the list');
  });

  testWidgets('the row is still highlighted where it belongs', (tester) async {
    // Guards against passing by drawing nothing.
    final rowKey = GlobalKey();
    await tester.pumpWidget(harness(keepGlobalKey: false, rowKey: rowKey));
    await tester.pumpAndSettle();
    final boundary =
        tester.renderObject<RenderRepaintBoundary>(find.byKey(boundaryKey));
    final image = await tester.runAsync(() => boundary.toImage());
    final data = await tester
        .runAsync(() => image!.toByteData(format: ui.ImageByteFormat.rawRgba));
    final bytes = data!.buffer.asUint8List();
    var hits = 0;
    for (var i = 0; i < bytes.length; i += 4) {
      if (Color.fromARGB(
              bytes[i + 3], bytes[i], bytes[i + 1], bytes[i + 2]) ==
          highlight) {
        hits++;
      }
    }
    expect(hits, greaterThan(0));
  });
}
