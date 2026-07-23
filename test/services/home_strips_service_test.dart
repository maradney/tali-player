import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/models/home_strip.dart';
import 'package:iptv_player/data/models/search_result.dart';
import 'package:iptv_player/data/services/home_strips_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/test_support.dart';

const _catStrip = HomeStrip(
  type: HomeStripType.category,
  categoryType: ContentType.movie,
  categoryId: '42',
  categoryName: '4K Movies',
);

void main() {
  group('HomeStrip', () {
    test('round-trips through JSON, category fields included', () {
      final back = HomeStrip.fromJson(_catStrip.toJson())!;
      expect(back.key, _catStrip.key);
      expect(back.categoryType, ContentType.movie);
      expect(back.categoryId, '42');
      expect(back.categoryName, '4K Movies');
      expect(back.enabled, isTrue);
    });

    test('rejects unknown types and category strips missing their category',
        () {
      expect(HomeStrip.fromJson({'type': 'hologram'}), isNull);
      expect(HomeStrip.fromJson({'type': 'category'}), isNull);
    });

    test('withDefaults keeps the stored order and appends new built-ins', () {
      // A config saved before the favorites rail existed, reordered by the
      // user, with a category strip in the middle.
      final stored = [
        const HomeStrip(type: HomeStripType.recentlyAdded),
        _catStrip,
        const HomeStrip(type: HomeStripType.continueWatching, enabled: false),
        const HomeStrip(type: HomeStripType.watchlist),
        const HomeStrip(type: HomeStripType.downloads),
      ];
      final merged = HomeStrip.withDefaults(stored);
      expect(merged.map((s) => s.type).take(5), stored.map((s) => s.type));
      expect(merged.last.type, HomeStripType.favorites,
          reason: 'the rail this config predates appears at the end');
      expect(merged[2].enabled, isFalse, reason: 'stored state preserved');
    });
  });

  group('HomeStripsService', () {
    final service = HomeStripsService.instance;
    final account = accountNamed('strips');

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await service.deleteFor(account); // resets in-memory state too
      await service.loadFor(account);
    });

    test('starts with the default strips, all enabled', () {
      expect(service.strips.map((s) => s.type), [
        HomeStripType.continueWatching,
        HomeStripType.watchlist,
        HomeStripType.recentlyAdded,
        HomeStripType.downloads,
        HomeStripType.favorites,
      ]);
      expect(service.enabledStrips, hasLength(5));
    });

    test('toggle flips one strip and persists', () async {
      await service.toggle(HomeStripType.downloads.name);
      expect(
          service.enabledStrips.map((s) => s.type),
          isNot(contains(HomeStripType.downloads)));

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList('home_strips_v1_${account.key}')!;
      final saved = raw.map((s) => jsonDecode(s)['enabled']).toList();
      expect(saved.where((e) => e == false), hasLength(1));
    });

    test('addCategory appends once; a duplicate is a no-op', () async {
      await service.addCategory(
          type: ContentType.movie, categoryId: '42', categoryName: '4K Movies');
      await service.addCategory(
          type: ContentType.movie, categoryId: '42', categoryName: '4K Movies');
      expect(
          service.strips.where((s) => s.type == HomeStripType.category),
          hasLength(1));
      expect(service.strips.last.categoryName, '4K Movies');
    });

    test('remove drops a category strip but never a built-in', () async {
      await service.addCategory(
          type: ContentType.live, categoryId: 'News', categoryName: 'News');
      await service.remove('category:live:News');
      await service.remove(HomeStripType.watchlist.name);
      expect(service.strips.where((s) => s.type == HomeStripType.category),
          isEmpty);
      expect(service.strips.map((s) => s.type),
          contains(HomeStripType.watchlist));
    });

    test('setStrips persists a reorder and loadFor restores it', () async {
      final reversed = service.strips.reversed.toList();
      await service.setStrips(reversed);

      // Reload from disk (fresh account object, same key).
      await service.deleteFor(accountNamed('other')); // no-op, different key
      await service.loadFor(accountNamed('other'));
      await service.loadFor(account);
      expect(service.strips.map((s) => s.type),
          reversed.map((s) => s.type));
    });

    test('import replaces the layout; an empty backup leaves it alone',
        () async {
      await service.importFor(account, [
        {'type': 'downloads', 'enabled': true},
        {'type': 'nonsense'}, // skipped
      ]);
      expect(service.strips.first.type, HomeStripType.downloads);
      expect(service.strips.map((s) => s.type),
          contains(HomeStripType.favorites)); // defaults appended

      final before = service.strips;
      await service.importFor(account, []);
      expect(service.strips.map((s) => s.key), before.map((s) => s.key));
    });
  });
}
