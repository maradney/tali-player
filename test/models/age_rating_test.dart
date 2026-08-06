import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/models/age_rating.dart';
import 'package:iptv_player/data/models/movie_info.dart';
import 'package:iptv_player/data/models/series_info.dart';

/// Panels put junk in the age-rating field. The detail screens render it as a
/// chip beside the title, so a value of "+" showed up as an unlabelled badge
/// that read as a broken button - which is how it was found on Android.
void main() {
  group('meaningfulAgeRating', () {
    test('drops values with no letter or digit', () {
      // The real case from a live panel.
      expect(meaningfulAgeRating('+'), isNull);
      expect(meaningfulAgeRating('-'), isNull);
      expect(meaningfulAgeRating('()'), isNull);
      expect(meaningfulAgeRating('...'), isNull);
    });

    test('drops blanks and placeholders', () {
      expect(meaningfulAgeRating(null), isNull);
      expect(meaningfulAgeRating(''), isNull);
      expect(meaningfulAgeRating('   '), isNull);
      expect(meaningfulAgeRating('N/A'), isNull);
      expect(meaningfulAgeRating('n/a'), isNull);
      expect(meaningfulAgeRating('none'), isNull);
      expect(meaningfulAgeRating('NULL'), isNull);
    });

    test('keeps real ratings, in the many shapes they come in', () {
      for (final rating in ['12', 'PG-13', '18+', 'TV-MA', 'R', '+16', '١٦']) {
        expect(meaningfulAgeRating(rating), rating, reason: rating);
      }
    });

    test('keeps "Unrated" - that is a statement, not a missing value', () {
      expect(meaningfulAgeRating('Unrated'), 'Unrated');
      expect(meaningfulAgeRating('Not Rated'), 'Not Rated');
    });

    test('trims surrounding whitespace', () {
      expect(meaningfulAgeRating('  PG-13  '), 'PG-13');
    });
  });

  group('parsed through the models', () {
    test('MovieInfo drops a junk age rating', () {
      final info = MovieInfo.fromJson({
        'info': {'mpaa_rating': '+', 'plot': 'A plot'}
      });
      expect(info.ageRating, isNull);
      expect(info.plot, 'A plot'); // other fields unaffected
    });

    test('MovieInfo keeps a real one, and falls through the field variants',
        () {
      expect(
        MovieInfo.fromJson({
          'info': {'mpaa_rating': 'PG-13'}
        }).ageRating,
        'PG-13',
      );
      // mpaa_rating is junk, so the next variant should be used rather than
      // the junk value winning and blocking it.
      expect(
        MovieInfo.fromJson({
          'info': {'mpaa_rating': '+', 'age': '16'}
        }).ageRating,
        '16',
      );
    });

    test('SeriesInfo does the same', () {
      expect(
        SeriesInfo.fromJson({
          'info': {'mpaa_rating': '+'}
        }).ageRating,
        isNull,
      );
      expect(
        SeriesInfo.fromJson({
          'info': {'age': 'TV-MA'}
        }).ageRating,
        'TV-MA',
      );
    });
  });
}
