import 'package:flutter/services.dart';

/// Which orientations fullscreen should allow for a video of [width]x[height].
///
/// Going fullscreen on a phone is a request to give the video the whole screen,
/// and for the 16:9 material this app plays that means turning it sideways -
/// held upright, a 16:9 video uses barely a third of the display.
///
/// Vertical video is the exception and is left alone: forcing landscape on a
/// 9:16 clip would pillarbox it into an even smaller picture than portrait
/// gave it. Unknown dimensions are treated as landscape, because that is
/// overwhelmingly what a TV stream is, and because dimensions are only unknown
/// in the moment before the first frame is decoded.
List<DeviceOrientation> fullscreenOrientationsFor({int? width, int? height}) {
  if (isPortraitVideo(width: width, height: height)) {
    return DeviceOrientation.values;
  }
  return const [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ];
}

/// Whether the video is taller than it is wide.
///
/// The single fact both the orientation list and the Android mode are derived
/// from, so the two cannot come to disagree about what counts as vertical.
///
/// Unknown dimensions are not portrait: they are only unknown in the moment
/// before the first frame decodes, and a TV stream is overwhelmingly
/// landscape, so guessing portrait would turn the phone back and forth as the
/// video loads.
bool isPortraitVideo({int? width, int? height}) =>
    width != null && height != null && width > 0 && height > width;

/// How Android should be asked to orient itself in fullscreen.
///
/// Separate from [fullscreenOrientationsFor] because the two answer different
/// questions: that one says which orientations are *allowed*, this one says
/// whether to follow the sensor. They agree on the aspect-ratio rule and are
/// derived from it, so they cannot drift.
enum AndroidOrientationMode {
  /// Follow the accelerometer between the two landscape orientations, even if
  /// the user has rotation lock on. Flipping the phone end over end turns the
  /// picture with it instead of leaving it upside down.
  sensorLandscape('sensorLandscape'),

  /// Leave orientation to the system.
  unspecified('unspecified');

  const AndroidOrientationMode(this.wireName);

  /// The string the platform channel carries. Values are matched by name on
  /// the Kotlin side, so these must not be renamed casually.
  final String wireName;
}

/// The mode to request for a video of [width]x[height] in fullscreen.
///
/// Vertical video is left unspecified rather than pinned: forcing landscape on
/// a 9:16 clip pillarboxes it into a smaller picture than portrait already
/// gave it, and someone who turns the phone for it should be allowed to.
AndroidOrientationMode androidFullscreenMode({int? width, int? height}) =>
    isPortraitVideo(width: width, height: height)
        ? AndroidOrientationMode.unspecified
        : AndroidOrientationMode.sensorLandscape;
