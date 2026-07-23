import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/models/catalog_row.dart';
import 'package:iptv_player/data/models/channel.dart';
import 'package:iptv_player/data/models/movie.dart';
import 'package:iptv_player/data/models/search_result.dart';
import 'package:iptv_player/data/models/series_item.dart';

void main() {
  group('CatalogRow db mapping', () {
    test('round-trips through the db map, encoding extra as JSON', () {
      const row = CatalogRow(
        accountKey: 'http://h|u',
        type: ContentType.movie,
        id: '120',
        name: 'The Matrix',
        categoryId: '4',
        imageUrl: 'http://p.jpg',
        extra: {'containerExtension': 'mkv'},
      );
      final map = row.toDbMap();
      expect(map['type'], 'movie');
      expect(map['category_id'], '4');
      expect(map['extra'], jsonEncode({'containerExtension': 'mkv'}));

      final restored = CatalogRow.fromDbMap(map);
      expect(restored.accountKey, 'http://h|u');
      expect(restored.type, ContentType.movie);
      expect(restored.id, '120');
      expect(restored.name, 'The Matrix');
      expect(restored.categoryId, '4');
      expect(restored.imageUrl, 'http://p.jpg');
      expect(restored.extra, {'containerExtension': 'mkv'});
    });

    test('stores null (not "{}") for empty extra', () {
      const row = CatalogRow(
        accountKey: 'k',
        type: ContentType.live,
        id: '1',
        name: 'X',
        categoryId: '1',
      );
      expect(row.toDbMap()['extra'], isNull);
      expect(CatalogRow.fromDbMap(row.toDbMap()).extra, isEmpty);
    });

    test('defaults a missing category_id to empty string on read', () {
      final restored = CatalogRow.fromDbMap({
        'account_key': 'k',
        'type': 'live',
        'id': '1',
        'name': 'X',
        'image_url': null,
        'category_id': null,
        'extra': null,
      });
      expect(restored.categoryId, '');
    });
  });

  group('CatalogRow.toSearchResult', () {
    test('reconstructs a Channel for live rows', () {
      const row = CatalogRow(
        accountKey: 'k',
        type: ContentType.live,
        id: '5',
        name: 'BBC',
        categoryId: '3',
        imageUrl: 'http://l.png',
      );
      final result = row.toSearchResult();
      expect(result.type, ContentType.live);
      // categoryId is surfaced as a typed field on the result itself, so
      // lock checks don't need to dig into raw with a dynamic cast.
      expect(result.categoryId, '3');
      expect(result.raw, isA<Channel>());
      final channel = result.raw as Channel;
      expect(channel.streamId, '5');
      expect(channel.categoryId, '3');
      expect(channel.logoUrl, 'http://l.png');
    });

    test('reconstructs a Movie with extension and rating', () {
      const row = CatalogRow(
        accountKey: 'k',
        type: ContentType.movie,
        id: '120',
        name: 'The Matrix',
        categoryId: '4',
        extra: {'containerExtension': 'mkv', 'rating': '7.4'},
      );
      final result = row.toSearchResult();
      expect(result.raw, isA<Movie>());
      final movie = result.raw as Movie;
      expect(movie.categoryId, '4');
      expect(movie.containerExtension, 'mkv');
      expect(movie.rating, '7.4');
      expect(result.rating, '7.4');
    });

    test('defaults movie extension to mp4 when extra lacks it', () {
      const row = CatalogRow(
        accountKey: 'k',
        type: ContentType.movie,
        id: '1',
        name: 'X',
        categoryId: '1',
      );
      expect((row.toSearchResult().raw as Movie).containerExtension, 'mp4');
    });

    test('threads a direct M3U url from extra onto the channel/movie', () {
      const liveRow = CatalogRow(
        accountKey: 'k',
        type: ContentType.live,
        id: '5',
        name: 'BBC',
        categoryId: 'News',
        extra: {'url': 'http://host/live/5.ts'},
      );
      expect((liveRow.toSearchResult().raw as Channel).url,
          'http://host/live/5.ts');

      const movieRow = CatalogRow(
        accountKey: 'k',
        type: ContentType.movie,
        id: '9',
        name: 'Dune',
        categoryId: 'Movies',
        extra: {'containerExtension': 'mkv', 'url': 'http://host/movie/9.mkv'},
      );
      expect((movieRow.toSearchResult().raw as Movie).url,
          'http://host/movie/9.mkv');
    });

    test('leaves url null for Xtream rows (no url in extra)', () {
      const row = CatalogRow(
        accountKey: 'k',
        type: ContentType.live,
        id: '5',
        name: 'BBC',
        categoryId: '3',
      );
      expect((row.toSearchResult().raw as Channel).url, isNull);
    });

    test('reconstructs a SeriesItem for series rows', () {
      const row = CatalogRow(
        accountKey: 'k',
        type: ContentType.series,
        id: '55',
        name: 'Breaking Bad',
        categoryId: '2',
        imageUrl: 'http://c.jpg',
      );
      final result = row.toSearchResult();
      expect(result.raw, isA<SeriesItem>());
      final series = result.raw as SeriesItem;
      expect(series.seriesId, '55');
      expect(series.categoryId, '2');
      expect(series.coverUrl, 'http://c.jpg');
    });
  });
}
