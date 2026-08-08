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
