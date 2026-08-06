import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Whether playback should be holding the screen awake.
///
/// Only while something is actually playing in the in-app player. A paused or
/// errored video releases it, so a stream that dies at 2am doesn't leave the
/// phone lit until the battery goes. External playback releases it too: the
/// other app owns the screen then, and it is responsible for its own wakelock.
bool shouldKeepScreenAwake({required bool playing, required bool external}) =>
    playing && !external;

/// Holds the screen awake during playback.
///
/// Without this the display sleeps mid-film on Android - Flutter does not
/// inhibit it, and neither does media_kit. It applies on desktop too, where
/// nothing was stopping Windows from sleeping during a long VOD either.
///
/// State is tracked so a repeated request is not sent to the platform again:
/// the player's playing stream can emit the same value several times around a
/// seek or a rebuffer, and each call is a real platform channel round trip.
class ScreenAwake {
  ScreenAwake._();

  /// Injected by tests so they can assert on what would reach the plugin,
  /// which has no implementation in the test VM.
  @visibleForTesting
  static Future<void> Function({required bool enable})? debugToggleOverride;

  static bool _enabled = false;

  /// Whether the wakelock is currently held, as far as this class knows.
  @visibleForTesting
  static bool get enabled => _enabled;

  static Future<void> set(bool enable) async {
    if (enable == _enabled) return;
    _enabled = enable;
    final toggle = debugToggleOverride ?? WakelockPlus.toggle;
    await toggle(enable: enable);
  }

  @visibleForTesting
  static void resetForTesting() {
    _enabled = false;
    debugToggleOverride = null;
  }
}
