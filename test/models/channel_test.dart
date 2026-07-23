import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/models/channel.dart';

void main() {
  group('Channel.fromJson', () {
    test('parses a well-formed channel', () {
      final c = Channel.fromJson({
        'stream_id': 501,
        'name': 'BBC One',
        'category_id': '3',
        'stream_icon': 'http://logo/bbc.png',
      });
      expect(c.streamId, '501');
      expect(c.name, 'BBC One');
      expect(c.categoryId, '3');
      expect(c.logoUrl, 'http://logo/bbc.png');
    });

    test('defaults name and categoryId when absent', () {
      final c = Channel.fromJson({'stream_id': '9'});
      expect(c.name, 'Unnamed channel');
      expect(c.categoryId, '');
    });

    test('treats an empty stream_icon as no logo', () {
      final c = Channel.fromJson({'stream_id': '9', 'stream_icon': ''});
      expect(c.logoUrl, isNull);
    });

    test('leaves logoUrl null when stream_icon is missing', () {
      final c = Channel.fromJson({'stream_id': '9'});
      expect(c.logoUrl, isNull);
    });
  });

  group('castHeaders', () {
    test('coerces a non-empty map to Map<String, String>', () {
      final h = castHeaders({'User-Agent': 'X', 'Referer': 'Y'});
      expect(h, {'User-Agent': 'X', 'Referer': 'Y'});
    });

    test('returns null for null or an empty map', () {
      expect(castHeaders(null), isNull);
      expect(castHeaders(<String, dynamic>{}), isNull);
    });
  });

  group('Channel.streamUrl', () {
    test('builds the live .ts URL', () {
      const c = Channel(streamId: '77', name: 'X', categoryId: '1');
      expect(
        c.streamUrl(
          serverUrl: 'http://host:8080',
          username: 'u',
          password: 'p',
        ),
        'http://host:8080/live/u/p/77.ts',
      );
    });
  });
}
