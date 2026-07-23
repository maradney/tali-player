import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/models/category.dart';

void main() {
  group('Category.fromJson', () {
    test('coerces a numeric category_id to a String', () {
      final c = Category.fromJson({'category_id': 12, 'category_name': 'News'});
      expect(c.categoryId, '12');
      expect(c.categoryId, isA<String>());
      expect(c.categoryName, 'News');
    });

    test('keeps a string category_id as-is', () {
      final c = Category.fromJson({'category_id': '7', 'category_name': 'Sports'});
      expect(c.categoryId, '7');
    });

    test('falls back to "Unnamed" when the name is missing', () {
      final c = Category.fromJson({'category_id': '1'});
      expect(c.categoryName, 'Unnamed');
    });

    test('coerces a numeric category_name to a String', () {
      final c = Category.fromJson({'category_id': '1', 'category_name': 2024});
      expect(c.categoryName, '2024');
    });
  });
}
