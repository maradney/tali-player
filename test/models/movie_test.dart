import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/models/movie.dart';

void main() {
  group('Movie.fromJson', () {
    test('parses a well-formed movie', () {
      final m = Movie.fromJson({
        'stream_id': 120,
        'name': 'The Matrix',
        'category_id': '4',
        'container_extension': 'mkv',
        'stream_icon': 'http://p/matrix.jpg',
        'rating': '7.4',
      });
      expect(m.streamId, '120');
      expect(m.name, 'The Matrix');
      expect(m.categoryId, '4');
      expect(m.containerExtension, 'mkv');
      expect(m.posterUrl, 'http://p/matrix.jpg');
      expect(m.rating, '7.4');
    });

    test('defaults container extension to mp4 when missing or empty', () {
      expect(Movie.fromJson({'stream_id': '1'}).containerExtension, 'mp4');
      expect(
        Movie.fromJson({'stream_id': '1', 'container_extension': ''})
            .containerExtension,
        'mp4',
      );
    });

    test('normalizes an integer-like rating to a double string', () {
      expect(Movie.fromJson({'stream_id': '1', 'rating': '8'}).rating, '8.0');
    });

    test('drops a zero or non-numeric rating', () {
      expect(Movie.fromJson({'stream_id': '1', 'rating': '0'}).rating, isNull);
      expect(Movie.fromJson({'stream_id': '1', 'rating': 'N/A'}).rating, isNull);
      expect(Movie.fromJson({'stream_id': '1'}).rating, isNull);
    });

    test('treats an empty stream_icon as no poster', () {
      expect(
        Movie.fromJson({'stream_id': '1', 'stream_icon': ''}).posterUrl,
        isNull,
      );
    });

    test('defaults name when absent', () {
      expect(Movie.fromJson({'stream_id': '1'}).name, 'Unnamed movie');
    });

    test('parses the "added" unix timestamp, null when absent/invalid', () {
      expect(
        Movie.fromJson({'stream_id': '1', 'added': '1609459200'}).addedAt,
        1609459200,
      );
      expect(Movie.fromJson({'stream_id': '1'}).addedAt, isNull);
      expect(Movie.fromJson({'stream_id': '1', 'added': ''}).addedAt, isNull);
    });
  });

  group('Movie.streamUrl', () {
    test('includes the container extension', () {
      const m = Movie(
        streamId: '120',
        name: 'X',
        categoryId: '1',
        containerExtension: 'mkv',
      );
      expect(
        m.streamUrl(serverUrl: 'http://host:8080', username: 'u', password: 'p'),
        'http://host:8080/movie/u/p/120.mkv',
      );
    });
  });
}
