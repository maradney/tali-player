import 'dart:io';

import 'package:flutter/services.dart';

import 'fullscreen_orientation.dart';

/// Asks Android to follow the phone while the player is fullscreen.
///
/// Flutter's SystemChrome.setPreferredOrientations only says which
/// orientations are *permitted*; Android still applies the user's rotation
/// lock on top. With the lock on, fullscreen settles into one landscape
/// orientation and stays there, so turning the phone end over end leaves the
/// picture upside down.
///
/// SCREEN_ORIENTATION_SENSOR_LANDSCAPE follows the accelerometer regardless of
/// the lock, and only between the two landscape orientations - there is no
/// upside-down state to land in. Rotation lock exists to stop a feed swinging
/// sideways in bed, not to make a video you deliberately made fullscreen play
/// the wrong way up.
///
/// This is the only writer of the activity's requested orientation. Flutter's
/// own call sets the same Android property, so [ChannelPlayerScreen] stops
/// using it on Android - two callers on one property resolve by whichever ran
/// last, which is exactly the kind of bug that only appears on someone else's
/// device.
class AndroidOrientation {
  AndroidOrientation._();

  static const _channel =
      MethodChannel('io.github.maradney.tali/orientation');

  /// Whether this platform has the override at all. Android only; everywhere
  /// else the caller keeps using SystemChrome.
  static bool get isSupported => Platform.isAndroid;

  /// Applies the mode for a video of [width]x[height] entering fullscreen.
  static Future<void> enterFullscreen({int? width, int? height}) =>
      _apply(androidFullscreenMode(width: width, height: height));

  /// Hands orientation back to the system on leaving fullscreen.
  static Future<void> exitFullscreen() =>
      _apply(AndroidOrientationMode.unspecified);

  static Future<void> _apply(AndroidOrientationMode mode) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('apply', {'mode': mode.wireName});
    } on PlatformException {
      // Not worth failing playback over. The worst case is the pre-existing
      // behaviour: the video does not turn with the phone.
    } on MissingPluginException {
      // Same, for a build where the activity has not registered the channel.
    }
  }
}
