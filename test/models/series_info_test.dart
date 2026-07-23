import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/models/series_info.dart';

void main() {
  group('Episode.fromJson', () {
    test('parses and coerces fields', () {
      final e = Episode.fromJson({
        'id': 900,
        'title': 'Pilot',
        'episode_num': '1',
        'container_extension': 'mp4',
      });
      expect(e.id, '900');
      expect(e.title, 'Pilot');
      expect(e.episodeNum, 1);
      expect(e.containerExtension, 'mp4');
    });

    test('defaults title, episodeNum and extension', () {
      final e = Episode.fromJson({'id': '5'});
      expect(e.title, 'Episode');
      expect(e.episodeNum, 0);
      expect(e.containerExtension, 'mp4');
    });

    test('builds the series episode stream URL', () {
      const e = Episode(id: '900', title: 'X', episodeNum: 1, containerExtension: 'mkv');
      expect(
        e.streamUrl(serverUrl: 'http://host:8080', username: 'u', password: 'p'),
        'http://host:8080/series/u/p/900.mkv',
      );
    });
  });

  group('SeriesInfo.fromJson', () {
    test('joins season metadata with its episodes, sorted', () {
      final info = SeriesInfo.fromJson({
        'info': {'plot': 'A show', 'cover': 'http://c.jpg', 'rating': '8.1'},
        'seasons': [
          {'season_number': '2', 'name': 'Second Season'},
          {'season_number': '1', 'name': 'First Season'},
        ],
        'episodes': {
          '1': [
            {'id': '11', 'title': 'S1E2', 'episode_num': '2'},
            {'id': '10', 'title': 'S1E1', 'episode_num': '1'},
          ],
          '2': [
            {'id': '20', 'title': 'S2E1', 'episode_num': '1'},
          ],
        },
      });

      expect(info.plot, 'A show');
      expect(info.coverUrl, 'http://c.jpg');
      expect(info.rating, '8.1');

      // Seasons sorted ascending.
      expect(info.seasons.map((s) => s.seasonNumber), [1, 2]);
      expect(info.seasons.first.name, 'First Season');

      // Episodes within a season sorted by episode number.
      expect(info.seasons.first.episodes.map((e) => e.episodeNum), [1, 2]);
      expect(info.seasons.first.episodes.first.id, '10');
    });

    test('falls back to episode keys when the seasons list is missing', () {
      final info = SeriesInfo.fromJson({
        'episodes': {
          '3': [
            {'id': '30', 'title': 'E1', 'episode_num': '1'},
          ],
        },
      });
      expect(info.seasons.map((s) => s.seasonNumber), [3]);
      expect(info.seasons.single.name, 'Season 3');
      expect(info.seasons.single.episodes.single.id, '30');
    });

    test('skips malformed episode entries rather than failing the season', () {
      final info = SeriesInfo.fromJson({
        'seasons': [
          {'season_number': '1', 'name': 'One'},
        ],
        'episodes': {
          '1': [
            {'id': '10', 'title': 'Good', 'episode_num': '1'},
            // A non-string container_extension makes Episode.fromJson's cast
            // throw, so this entry is dropped instead of failing the season.
            {'id': '11', 'container_extension': 123},
          ],
        },
      });
      expect(info.seasons.single.episodes.map((e) => e.id), ['10']);
    });

    test('handles a completely empty payload', () {
      final info = SeriesInfo.fromJson({});
      expect(info.seasons, isEmpty);
      expect(info.plot, isNull);
      expect(info.rating, isNull);
    });

    test('reads ageRating from the first populated variant key', () {
      final info = SeriesInfo.fromJson({
        'info': {'age': 'TV-MA'},
      });
      expect(info.ageRating, 'TV-MA');
    });

    test('parses a 4-digit year from year or releaseDate', () {
      expect(SeriesInfo.fromJson({'info': {'year': '2017'}}).year, 2017);
      expect(
        SeriesInfo.fromJson({'info': {'releaseDate': '2020-06-27'}}).year,
        2020,
      );
      expect(SeriesInfo.fromJson({'info': {'year': ''}}).year, isNull);
      expect(SeriesInfo.fromJson({}).year, isNull);
    });
  });
}
