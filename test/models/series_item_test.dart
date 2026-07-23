import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/models/series_item.dart';

void main() {
  group('SeriesItem.fromJson', () {
    test('parses a well-formed series', () {
      final s = SeriesItem.fromJson({
        'series_id': 55,
        'name': 'Breaking Bad',
        'category_id': '2',
        'cover': 'http://c/bb.jpg',
        'rating': '9.5',
      });
      expect(s.seriesId, '55');
      expect(s.name, 'Breaking Bad');
      expect(s.categoryId, '2');
      expect(s.coverUrl, 'http://c/bb.jpg');
      expect(s.rating, '9.5');
    });

    test('defaults name and categoryId when absent', () {
      final s = SeriesItem.fromJson({'series_id': '1'});
      expect(s.name, 'Unnamed series');
      expect(s.categoryId, '');
    });

    test('treats an empty cover as no image', () {
      expect(SeriesItem.fromJson({'series_id': '1', 'cover': ''}).coverUrl, isNull);
    });

    test('drops a zero or non-numeric rating', () {
      expect(SeriesItem.fromJson({'series_id': '1', 'rating': '0'}).rating, isNull);
      expect(SeriesItem.fromJson({'series_id': '1'}).rating, isNull);
    });

    test('parses "last_modified" into addedAt, null when absent', () {
      expect(
        SeriesItem.fromJson({'series_id': '1', 'last_modified': '1700000000'})
            .addedAt,
        1700000000,
      );
      expect(SeriesItem.fromJson({'series_id': '1'}).addedAt, isNull);
    });
  });
}
