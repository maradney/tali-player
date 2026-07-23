import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/features/player/track_labels.dart';
import 'package:media_kit/media_kit.dart';

void main() {
  group('audioTrackLabel', () {
    test('title and language combine', () {
      expect(audioTrackLabel(const AudioTrack('1', 'English', 'eng')),
          'English · eng');
    });

    test('language only', () {
      expect(audioTrackLabel(const AudioTrack('2', null, 'spa')), 'spa');
    });

    test('title only', () {
      expect(audioTrackLabel(const AudioTrack('3', 'Commentary', null)),
          'Commentary');
    });

    test('does not repeat when title equals language', () {
      expect(audioTrackLabel(const AudioTrack('4', 'eng', 'eng')), 'eng');
    });

    test('falls back to "Audio <id>" when unlabeled', () {
      expect(audioTrackLabel(const AudioTrack('5', null, null)), 'Audio 5');
    });

    test('auto track reads as Auto', () {
      expect(audioTrackLabel(AudioTrack.auto()), 'Auto');
    });
  });

  group('subtitleTrackLabel', () {
    test('the "no" track reads as Off', () {
      expect(subtitleTrackLabel(SubtitleTrack.no()), 'Off');
    });

    test('title and language combine', () {
      expect(subtitleTrackLabel(const SubtitleTrack('1', 'English SDH', 'eng')),
          'English SDH · eng');
    });

    test('falls back to "Subtitle <id>" when unlabeled', () {
      expect(subtitleTrackLabel(const SubtitleTrack('7', null, null)),
          'Subtitle 7');
    });
  });
}
