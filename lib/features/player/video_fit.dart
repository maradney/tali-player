import 'package:flutter/widgets.dart';

/// The video sizing modes the player offers, in menu order:
///  - [BoxFit.contain] "Fit"      — whole frame visible, may letterbox
///  - [BoxFit.cover]   "Fill"     — fills the screen, crops the overscan
///                                  (handy for streams with baked-in black bars)
///  - [BoxFit.fill]    "Stretch"  — distorts to fill, ignoring aspect ratio
const kVideoFitModes = <BoxFit>[BoxFit.contain, BoxFit.cover, BoxFit.fill];

/// Short menu label for a video-fit mode.
String videoFitLabel(BoxFit fit) {
  switch (fit) {
    case BoxFit.contain:
      return 'Fit';
    case BoxFit.cover:
      return 'Fill (crop)';
    case BoxFit.fill:
      return 'Stretch';
    default:
      return 'Fit';
  }
}
