import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/models/movie_info.dart';

void main() {
  group('MovieInfo.fromJson', () {
    test('reads fields from the info block and trims blanks to null', () {
      final info = MovieInfo.fromJson({
        'info': {
          'plot': 'A hacker learns the truth.',
          'cast': 'Keanu Reeves',
          'director': 'The Wachowskis',
          'genre': 'Sci-Fi',
          'rating': '8.7',
          '   ': 'ignored',
          'mpaa_rating': 'R',
        },
      });
      expect(info.plot, 'A hacker learns the truth.');
      expect(info.cast, 'Keanu Reeves');
      expect(info.director, 'The Wachowskis');
      expect(info.genre, 'Sci-Fi');
      expect(info.rating, '8.7');
      expect(info.ageRating, 'R');
    });

    test('whitespace-only values become null', () {
      final info = MovieInfo.fromJson({
        'info': {'plot': '   ', 'cast': ''},
      });
      expect(info.plot, isNull);
      expect(info.cast, isNull);
    });

    test('missing info block yields all-null', () {
      final info = MovieInfo.fromJson({});
      expect(info.plot, isNull);
      expect(info.rating, isNull);
      expect(info.ageRating, isNull);
    });

    test('parses a 4-digit year from year or releasedate', () {
      expect(MovieInfo.fromJson({'info': {'year': '2010'}}).year, 2010);
      expect(
        MovieInfo.fromJson({'info': {'releasedate': '2014-11-07'}}).year,
        2014,
      );
      // No usable value, or an out-of-range one, yields null.
      expect(MovieInfo.fromJson({'info': {'year': 'n/a'}}).year, isNull);
      expect(MovieInfo.fromJson({'info': {'year': '1600'}}).year, isNull);
      expect(MovieInfo.fromJson({}).year, isNull);
    });

    test('ageRating prefers mpaa_rating, then age, then rating_mpaa', () {
      expect(
        MovieInfo.fromJson({
          'info': {'age': '18', 'rating_mpaa': 'NC-17', 'mpaa_rating': 'PG-13'},
        }).ageRating,
        'PG-13',
      );
      expect(
        MovieInfo.fromJson({
          'info': {'age': '18', 'rating_mpaa': 'NC-17'},
        }).ageRating,
        '18',
      );
      expect(
        MovieInfo.fromJson({
          'info': {'rating_mpaa': 'NC-17'},
        }).ageRating,
        'NC-17',
      );
    });
  });
}
