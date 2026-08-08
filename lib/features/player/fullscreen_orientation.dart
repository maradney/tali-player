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
  final isPortraitVideo =
      width != null && height != null && width > 0 && height > width;
  if (isPortraitVideo) return DeviceOrientation.values;
  return const [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ];
}
