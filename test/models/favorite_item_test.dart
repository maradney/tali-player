import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/models/favorite_item.dart';

void main() {
  group('FavoriteItem', () {
    test('key combines type and id', () {
      const item = FavoriteItem(type: 'movie', id: '1234', name: 'X');
      expect(item.key, 'movie:1234');
    });

    test('round-trips through JSON including categoryId and extra', () {
      const item = FavoriteItem(
        type: 'movie',
        id: '120',
        name: 'The Matrix',
        imageUrl: 'http://p.jpg',
        categoryId: '4',
        extra: {'containerExtension': 'mkv', 'rating': '7.4'},
      );
      final restored = FavoriteItem.fromJson(item.toJson());
      expect(restored.type, item.type);
      expect(restored.id, item.id);
      expect(restored.name, item.name);
      expect(restored.imageUrl, item.imageUrl);
      expect(restored.categoryId, '4');
      expect(restored.extra, {'containerExtension': 'mkv', 'rating': '7.4'});
    });

    test('legacy JSON without categoryId decodes to null', () {
      final restored = FavoriteItem.fromJson({
        'type': 'live',
        'id': '5',
        'name': 'BBC',
      });
      expect(restored.categoryId, isNull);
      expect(restored.extra, isEmpty);
    });

    test('toJson carries a null categoryId key for forward compatibility', () {
      const item = FavoriteItem(type: 'live', id: '5', name: 'BBC');
      expect(item.toJson().containsKey('categoryId'), isTrue);
      expect(item.toJson()['categoryId'], isNull);
    });
  });
}
