import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/features/player/screen_awake.dart';

/// Holding the screen awake during playback. The rule is small but the failure
/// modes are opposite and both bad: too little and the display sleeps mid-film,
/// too much and a phone left on a paused stream stays lit until it's flat.
void main() {
  setUp(ScreenAwake.resetForTesting);
  tearDown(ScreenAwake.resetForTesting);

  group('shouldKeepScreenAwake', () {
    test('holds the screen only while actually playing', () {
      expect(shouldKeepScreenAwake(playing: true, external: false), isTrue);
      expect(shouldKeepScreenAwake(playing: false, external: false), isFalse);
    });

    test('never holds it for external playback', () {
      // Another app owns the screen then and does its own wakelock; holding
      // one here would keep the display on behind it.
      expect(shouldKeepScreenAwake(playing: true, external: true), isFalse);
      expect(shouldKeepScreenAwake(playing: false, external: true), isFalse);
    });
  });

  group('ScreenAwake.set', () {
    test('passes the request through to the platform', () async {
      final calls = <bool>[];
      ScreenAwake.debugToggleOverride = ({required bool enable}) async =>
          calls.add(enable);

      await ScreenAwake.set(true);
      expect(calls, [true]);
      expect(ScreenAwake.enabled, isTrue);

      await ScreenAwake.set(false);
      expect(calls, [true, false]);
      expect(ScreenAwake.enabled, isFalse);
    });

    test('does not repeat a request already in effect', () async {
      // The player's playing stream re-emits the same value around seeks and
      // rebuffers; each call is a real platform channel round trip.
      final calls = <bool>[];
      ScreenAwake.debugToggleOverride = ({required bool enable}) async =>
          calls.add(enable);

      await ScreenAwake.set(true);
      await ScreenAwake.set(true);
      await ScreenAwake.set(true);
      expect(calls, [true]);
    });

    test('releasing when never held does nothing', () async {
      // dispose() releases unconditionally, including for a screen that never
      // started playing.
      final calls = <bool>[];
      ScreenAwake.debugToggleOverride = ({required bool enable}) async =>
          calls.add(enable);

      await ScreenAwake.set(false);
      expect(calls, isEmpty);
    });

    test('can be re-acquired after release', () async {
      final calls = <bool>[];
      ScreenAwake.debugToggleOverride = ({required bool enable}) async =>
          calls.add(enable);

      await ScreenAwake.set(true);
      await ScreenAwake.set(false);
      await ScreenAwake.set(true);
      expect(calls, [true, false, true]);
    });
  });
}
