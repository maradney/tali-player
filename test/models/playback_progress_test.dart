import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/models/playback_progress.dart';

void main() {
  group('PlaybackRef', () {
    test('carries optional episode + category fields', () {
      const ref = PlaybackRef(
        type: 'episode',
        id: '900',
        seriesId: '55',
        seasonNumber: 1,
        episodeNum: 2,
        categoryId: '2',
      );
      expect(ref.type, 'episode');
      expect(ref.seriesId, '55');
      expect(ref.seasonNumber, 1);
      expect(ref.episodeNum, 2);
      expect(ref.categoryId, '2');
    });

    test('movie ref leaves episode fields null', () {
      const ref = PlaybackRef(type: 'movie', id: '120');
      expect(ref.seriesId, isNull);
      expect(ref.seasonNumber, isNull);
      expect(ref.episodeNum, isNull);
    });
  });

  group('PlaybackProgress', () {
    test('key combines type and id', () {
      final p = PlaybackProgress(
        type: 'movie',
        id: '120',
        position: const Duration(minutes: 5),
        total: const Duration(minutes: 90),
        updatedAt: DateTime.now(),
      );
      expect(p.key, 'movie:120');
    });

    test('round-trips through JSON', () {
      final updatedAt = DateTime.fromMillisecondsSinceEpoch(1700000000000);
      final p = PlaybackProgress(
        type: 'episode',
        id: '900',
        position: const Duration(seconds: 42),
        total: const Duration(minutes: 24),
        seriesId: '55',
        seasonNumber: 1,
        episodeNum: 2,
        updatedAt: updatedAt,
      );
      final restored = PlaybackProgress.fromJson(p.toJson());
      expect(restored.type, 'episode');
      expect(restored.id, '900');
      expect(restored.position, const Duration(seconds: 42));
      expect(restored.total, const Duration(minutes: 24));
      expect(restored.seriesId, '55');
      expect(restored.seasonNumber, 1);
      expect(restored.episodeNum, 2);
      expect(restored.updatedAt, updatedAt);
    });
  });
}
