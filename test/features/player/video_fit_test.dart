import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/features/player/video_fit.dart';

void main() {
  group('video fit modes', () {
    test('offers Fit / Fill / Stretch in order', () {
      expect(kVideoFitModes, [BoxFit.contain, BoxFit.cover, BoxFit.fill]);
    });

    test('modes are distinct', () {
      expect(kVideoFitModes.toSet(), hasLength(kVideoFitModes.length));
    });

    test('every offered mode has a distinct label', () {
      final labels = kVideoFitModes.map(videoFitLabel).toList();
      expect(labels, ['Fit', 'Fill (crop)', 'Stretch']);
      expect(labels.toSet(), hasLength(labels.length));
    });
  });
}
