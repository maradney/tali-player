import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/services/external_player.dart';

void main() {
  group('windowsVlcCandidates', () {
    final candidates = ExternalPlayer.windowsVlcCandidates();

    test('offers at least the two standard Program Files locations', () {
      expect(candidates.length, greaterThanOrEqualTo(2));
    });

    test('every candidate points at vlc.exe under a VideoLAN\\VLC folder', () {
      for (final c in candidates) {
        expect(c, endsWith(r'VideoLAN\VLC\vlc.exe'));
      }
    });

    test('candidates are distinct', () {
      expect(candidates.toSet(), hasLength(candidates.length));
    });
  });
}
