import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/models/favorite_item.dart';
import 'package:iptv_player/data/services/watchlist_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/test_support.dart';

void main() {
  final service = WatchlistService.instance;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  test('starts empty for a fresh account', () async {
    await service.loadFor(accountNamed('wl-empty'));
    expect(service.items, isEmpty);
  });

  test('toggle adds then removes an item', () async {
    final account = accountNamed('wl-toggle');
    await service.loadFor(account);
    const item = FavoriteItem(type: 'movie', id: '120', name: 'Dune');

    await service.toggle(item);
    expect(service.isInWatchlist('movie', '120'), isTrue);
    expect(service.items.single.id, '120');

    await service.toggle(item);
    expect(service.isInWatchlist('movie', '120'), isFalse);
    expect(service.items, isEmpty);
  });

  test('appends in add order (surfaces reverse for newest-first)', () async {
    final account = accountNamed('wl-order');
    await service.loadFor(account);
    await service.toggle(const FavoriteItem(type: 'movie', id: '1', name: 'A'));
    await service.toggle(const FavoriteItem(type: 'series', id: '2', name: 'B'));
    expect(service.items.map((i) => i.id), ['1', '2']);
  });

  test('persists to a watchlist-namespaced key, separate from favorites',
      () async {
    final account = accountNamed('wl-persist');
    await service.loadFor(account);
    await service.toggle(
      const FavoriteItem(type: 'series', id: '5', name: 'Dark', categoryId: '3'),
    );

    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList('watchlist_v1_${account.key}')!;
    expect(stored, hasLength(1));
    expect(jsonDecode(stored.single)['id'], '5');
    // Not written under the favorites key.
    expect(prefs.getStringList('favorites_v1_${account.key}'), isNull);
  });

  test('loadFor reads previously stored items', () async {
    final account = accountNamed('wl-load');
    SharedPreferences.setMockInitialValues({
      'watchlist_v1_${account.key}': [
        jsonEncode(
            const FavoriteItem(type: 'series', id: '55', name: 'BB').toJson()),
      ],
    });
    await service.loadFor(account);
    expect(service.isInWatchlist('series', '55'), isTrue);
  });

  test('importFor merges by key, keeping existing and adding new', () async {
    final account = accountNamed('wl-import');
    await service.loadFor(account);
    await service
        .toggle(const FavoriteItem(type: 'movie', id: '1', name: 'Existing'));

    await service.importFor(account, [
      const FavoriteItem(type: 'movie', id: '1', name: 'Dupe').toJson(),
      const FavoriteItem(type: 'movie', id: '2', name: 'Imported').toJson(),
    ]);

    expect(service.items.map((i) => i.id), ['1', '2']);
    expect(service.items.first.name, 'Existing');
  });

  test('exportFor reads a non-loaded account\'s stored items', () async {
    final other = accountNamed('wl-export');
    SharedPreferences.setMockInitialValues({
      'watchlist_v1_${other.key}': [
        jsonEncode(
            const FavoriteItem(type: 'movie', id: '9', name: 'Z').toJson()),
      ],
    });
    await service.loadFor(accountNamed('wl-export-active'));
    final exported = await service.exportFor(other);
    expect(exported.single['id'], '9');
  });

  test('deleteFor wipes an account and clears the in-memory list', () async {
    final account = accountNamed('wl-delete');
    await service.loadFor(account);
    await service.toggle(const FavoriteItem(type: 'movie', id: '1', name: 'X'));

    await service.deleteFor(account);
    expect(service.items, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('watchlist_v1_${account.key}'), isNull);
  });
}
