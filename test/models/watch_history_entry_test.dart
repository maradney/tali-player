import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/models/watch_history_entry.dart';

void main() {
  group('WatchHistoryEntry', () {
    test('key combines type and id', () {
      final entry = WatchHistoryEntry(
        type: 'episode',
        id: '900',
        name: 'Pilot',
        watchedAt: DateTime.now(),
      );
      expect(entry.key, 'episode:900');
    });

    test('round-trips through JSON including episode + category fields', () {
      final watchedAt = DateTime.fromMillisecondsSinceEpoch(1700000000000);
      final entry = WatchHistoryEntry(
        type: 'episode',
        id: '900',
        name: 'Breaking Bad',
        imageUrl: 'http://c.jpg',
        seriesId: '55',
        seasonNumber: 1,
        episodeNum: 2,
        categoryId: '2',
        extra: {'foo': 'bar'},
        watchedAt: watchedAt,
      );
      final restored = WatchHistoryEntry.fromJson(entry.toJson());
      expect(restored.type, 'episode');
      expect(restored.id, '900');
      expect(restored.name, 'Breaking Bad');
      expect(restored.imageUrl, 'http://c.jpg');
      expect(restored.seriesId, '55');
      expect(restored.seasonNumber, 1);
      expect(restored.episodeNum, 2);
      expect(restored.categoryId, '2');
      expect(restored.extra, {'foo': 'bar'});
      expect(restored.watchedAt, watchedAt);
    });

    test('legacy JSON without categoryId decodes to null', () {
      final restored = WatchHistoryEntry.fromJson({
        'type': 'movie',
        'id': '1',
        'name': 'X',
        'watchedAt': 1700000000000,
      });
      expect(restored.categoryId, isNull);
      expect(restored.seriesId, isNull);
      expect(restored.extra, isEmpty);
    });
  });
}
