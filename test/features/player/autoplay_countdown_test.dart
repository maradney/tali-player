import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/features/player/autoplay_countdown.dart';
import 'package:iptv_player/l10n/app_localizations.dart';

/// The card that offers the next episode.
///
/// Its buttons being reachable is the whole point: the first version was
/// placed under the player's control bar, which drew the seek slider across
/// it and swallowed every tap on Cancel. A countdown you cannot stop is worse
/// than no countdown, so these cover both buttons actually firing - including
/// with something painted over the rest of the screen.
void main() {
  Widget wrap(Widget child) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      );

  testWidgets('counts down in the label', (tester) async {
    await tester.pumpWidget(wrap(AutoplayCountdown(
      secondsLeft: 5,
      onCancel: () {},
      onPlayNow: () {},
    )));
    expect(find.textContaining('5'), findsOneWidget);
  });

  testWidgets('cancel and play now both fire', (tester) async {
    var cancelled = 0;
    var played = 0;
    await tester.pumpWidget(wrap(AutoplayCountdown(
      secondsLeft: 3,
      onCancel: () => cancelled++,
      onPlayNow: () => played++,
    )));

    await tester.tap(find.byType(TextButton));
    await tester.pump();
    expect(cancelled, 1);

    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(played, 1);
  });

  testWidgets('stays tappable when it is the topmost layer of a stack',
      (tester) async {
    // The regression: the card was added to the player's Stack *before* the
    // control bar, so the bar painted over it and took the taps. Last in the
    // stack is what makes it usable.
    var cancelled = 0;
    await tester.pumpWidget(wrap(Stack(
      children: [
        // Stands in for the control bar: opaque and hungry for pointers.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: const ColoredBox(color: Colors.black),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: AutoplayCountdown(
            secondsLeft: 2,
            onCancel: () => cancelled++,
            onPlayNow: () {},
          ),
        ),
      ],
    )));

    await tester.tap(find.byType(TextButton));
    await tester.pump();
    expect(cancelled, 1,
        reason: 'a layer painted below must not steal the tap');
  });
}
