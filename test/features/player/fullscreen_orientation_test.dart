import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/features/player/fullscreen_orientation.dart';

/// Which way the phone should turn when the player goes fullscreen. Held
/// upright, a 16:9 video uses barely a third of the screen, so fullscreen
/// without rotating is not really fullscreen.
void main() {
  const landscape = [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ];

  _androidModeTests();

  test('turns sideways for ordinary widescreen video', () {
    expect(fullscreenOrientationsFor(width: 1280, height: 720), landscape);
    expect(fullscreenOrientationsFor(width: 1920, height: 1080), landscape);
    expect(fullscreenOrientationsFor(width: 640, height: 480), landscape);
  });

  test('turns sideways when the dimensions are not known yet', () {
    // Only true in the moment before the first frame decodes, and a TV stream
    // is overwhelmingly landscape - guessing portrait would rotate the phone
    // back and forth as the video loads.
    expect(fullscreenOrientationsFor(), landscape);
    expect(fullscreenOrientationsFor(width: null, height: 720), landscape);
    expect(fullscreenOrientationsFor(width: 1280, height: null), landscape);
  });

  test('leaves vertical video alone', () {
    // Forcing landscape on a 9:16 clip would pillarbox it into a smaller
    // picture than portrait already gave it.
    expect(fullscreenOrientationsFor(width: 720, height: 1280),
        DeviceOrientation.values);
  });

  test('treats a square video as landscape', () {
    // Nothing to gain from staying upright, and it keeps the common case
    // predictable.
    expect(fullscreenOrientationsFor(width: 1080, height: 1080), landscape);
  });

  test('ignores nonsense dimensions rather than acting on them', () {
    expect(fullscreenOrientationsFor(width: 0, height: 0), landscape);
    expect(fullscreenOrientationsFor(width: 0, height: 720), landscape);
  });
}

/// The Android override, which is a second answer derived from the same fact.
///
/// Only the mapping is testable here. Whether the phone actually turns depends
/// on SCREEN_ORIENTATION_SENSOR_LANDSCAPE overriding the user's rotation lock,
/// which is the Android framework's behaviour and needs a real device to
/// confirm.
void _androidModeTests() {
  group('android fullscreen mode', () {
    test('widescreen video follows the sensor between the two landscapes', () {
      // The point of the override: with rotation lock on, permitting both
      // landscape orientations is not enough - the system settles on one, and
      // flipping the phone leaves the picture upside down.
      expect(androidFullscreenMode(width: 1920, height: 1080),
          AndroidOrientationMode.sensorLandscape);
      expect(androidFullscreenMode(width: 640, height: 480),
          AndroidOrientationMode.sensorLandscape);
    });

    test('unknown dimensions follow the sensor too', () {
      expect(androidFullscreenMode(), AndroidOrientationMode.sensorLandscape);
      expect(androidFullscreenMode(width: 1280),
          AndroidOrientationMode.sensorLandscape);
    });

    test('vertical video is left to the system', () {
      // Pinning a 9:16 clip to landscape pillarboxes it into a smaller picture
      // than portrait already gave it.
      expect(androidFullscreenMode(width: 1080, height: 1920),
          AndroidOrientationMode.unspecified);
    });

    test('square video counts as landscape, like the orientation list', () {
      expect(androidFullscreenMode(width: 500, height: 500),
          AndroidOrientationMode.sensorLandscape);
    });

    test('the two answers never disagree about what is vertical', () {
      // They read one predicate; this is what stops them drifting apart.
      for (final size in const [
        [1920, 1080],
        [1080, 1920],
        [500, 500],
        [0, 0],
        [1280, 0],
      ]) {
        final portrait = isPortraitVideo(width: size[0], height: size[1]);
        final list = fullscreenOrientationsFor(width: size[0], height: size[1]);
        final mode = androidFullscreenMode(width: size[0], height: size[1]);
        expect(
          mode == AndroidOrientationMode.unspecified,
          portrait,
          reason: 'mode disagrees with isPortraitVideo for $size',
        );
        expect(
          list.length == DeviceOrientation.values.length,
          portrait,
          reason: 'list disagrees with isPortraitVideo for $size',
        );
      }
    });

    test('the wire names match what MainActivity matches on', () {
      // Renaming either side silently stops the override working, with no
      // error - the Kotlin falls through to unspecified and the phone simply
      // does not turn.
      expect(AndroidOrientationMode.sensorLandscape.wireName, 'sensorLandscape');
      expect(AndroidOrientationMode.unspecified.wireName, 'unspecified');
    });
  });
}
