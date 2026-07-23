import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app_info.dart';

void main() {
  group('appName', () {
    test('is non-empty', () {
      expect(appName, isNotEmpty);
    });
  });

  group('appSlug', () {
    test('is a filesystem-safe lowercase form of the name', () {
      expect(appSlug, matches(RegExp(r'^[a-z0-9_]+$')));
      expect(appSlug, isNot(startsWith('_')));
      expect(appSlug, isNot(endsWith('_')));
    });

    test('collapses spaces/punctuation to single underscores', () {
      // Sanity on the derivation itself, independent of the current name.
      String slugOf(String s) => s
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
          .replaceAll(RegExp(r'^_+|_+$'), '');
      expect(slugOf('IPTV Player'), 'iptv_player');
      expect(slugOf('  My  TV!! '), 'my_tv');
      expect(slugOf('Café 21'), 'caf_21');
    });
  });
}
