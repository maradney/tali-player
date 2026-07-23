import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/features/player/track_labels.dart';
import 'package:media_kit/media_kit.dart';

void main() {
  group('videoTrackLabel', () {
    test('labels a rendition by its height (e.g. 720p)', () {
      const track = VideoTrack('1', null, null, w: 1280, h: 720);
      expect(videoTrackLabel(track), '720p');
    });

    test('appends the bitrate in Mbps when present', () {
      const track = VideoTrack('1', null, null, h: 1080, bitrate: 5000000);
      expect(videoTrackLabel(track), '1080p · 5.0 Mbps');
    });

    test('falls back to the title, then the id, when no resolution', () {
      expect(videoTrackLabel(const VideoTrack('2', 'High', null)), 'High');
      expect(videoTrackLabel(const VideoTrack('3', null, null)), 'Video 3');
    });
  });
}
