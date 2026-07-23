import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/models/genre_util.dart';

void main() {
  group('splitGenres', () {
    test('null / blank -> empty', () {
      expect(splitGenres(null), isEmpty);
      expect(splitGenres('   '), isEmpty);
    });

    test('single genre is returned trimmed', () {
      expect(splitGenres('  Action '), ['Action']);
    });

    test('splits on comma, pipe, slash, semicolon and newline', () {
      expect(splitGenres('Action, Adventure'), ['Action', 'Adventure']);
      expect(splitGenres('Comedy | Drama'), ['Comedy', 'Drama']);
      expect(splitGenres('Crime/Thriller'), ['Crime', 'Thriller']);
      expect(splitGenres('Horror;Mystery'), ['Horror', 'Mystery']);
      expect(splitGenres('Action\nAdventure'), ['Action', 'Adventure']);
    });

    test('does NOT split on & or the word "and"', () {
      expect(splitGenres('Sci-Fi & Fantasy'), ['Sci-Fi & Fantasy']);
      expect(splitGenres('Rock and Roll'), ['Rock and Roll']);
    });

    test('collapses internal whitespace', () {
      expect(splitGenres('Science   Fiction'), ['Science Fiction']);
    });

    test('drops empty fragments from stray separators', () {
      expect(splitGenres('Action,,Comedy, '), ['Action', 'Comedy']);
    });

    test('dedupes case-insensitively, keeping first-seen casing', () {
      expect(splitGenres('Action, action, ACTION'), ['Action']);
    });
  });
}
