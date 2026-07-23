import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/models/favorite_item.dart';
import 'package:iptv_player/data/services/favorites_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/test_support.dart';

void main() {
  final service = FavoritesService.instance;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  test('starts empty for a fresh account', () async {
    await service.loadFor(accountNamed('fav-empty'));
    expect(service.items, isEmpty);
  });

  test('toggle adds then removes an item', () async {
    final account = accountNamed('fav-toggle');
    await service.loadFor(account);
    const item = FavoriteItem(type: 'movie', id: '120', name: 'The Matrix');

    await service.toggle(item);
    expect(service.isFavorite('movie', '120'), isTrue);
    expect(service.items.single.id, '120');

    await service.toggle(item);
    expect(service.isFavorite('movie', '120'), isFalse);
    expect(service.items, isEmpty);
  });

  test('persists favorites to shared_preferences', () async {
    final account = accountNamed('fav-persist');
    await service.loadFor(account);
    await service.toggle(
      const FavoriteItem(type: 'live', id: '5', name: 'BBC', categoryId: '3'),
    );

    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList('favorites_v1_${account.key}')!;
    expect(stored, hasLength(1));
    final decoded = jsonDecode(stored.single) as Map<String, dynamic>;
    expect(decoded['id'], '5');
    expect(decoded['categoryId'], '3');
  });

  test('loadFor reads previously stored favorites', () async {
    final account = accountNamed('fav-load');
    SharedPreferences.setMockInitialValues({
      'favorites_v1_${account.key}': [
        jsonEncode(const FavoriteItem(type: 'series', id: '55', name: 'BB').toJson()),
      ],
    });
    await service.loadFor(account);
    expect(service.isFavorite('series', '55'), isTrue);
  });

  test('skips corrupted entries instead of crashing', () async {
    final account = accountNamed('fav-corrupt');
    SharedPreferences.setMockInitialValues({
      'favorites_v1_${account.key}': [
        'not-json',
        jsonEncode(const FavoriteItem(type: 'movie', id: '1', name: 'Ok').toJson()),
      ],
    });
    await service.loadFor(account);
    expect(service.items.map((i) => i.id), ['1']);
  });

  test('importFor merges by key, keeping existing and adding new', () async {
    final account = accountNamed('fav-import');
    await service.loadFor(account);
    await service.toggle(
        const FavoriteItem(type: 'movie', id: '1', name: 'Existing'));

    // A backup carrying a duplicate (id 1) and a new one (id 2).
    await service.importFor(account, [
      const FavoriteItem(type: 'movie', id: '1', name: 'Dupe').toJson(),
      const FavoriteItem(type: 'movie', id: '2', name: 'Imported').toJson(),
    ]);

    // Union by key: nothing removed, the duplicate isn't added twice.
    expect(service.items.map((i) => i.id), ['1', '2']);
    // The pre-existing entry is kept (not overwritten by the import).
    expect(service.items.first.name, 'Existing');
  });

  test('exportFor reads a non-loaded account\'s stored favorites', () async {
    final other = accountNamed('fav-export');
    SharedPreferences.setMockInitialValues({
      'favorites_v1_${other.key}': [
        jsonEncode(const FavoriteItem(type: 'movie', id: '9', name: 'Z').toJson()),
      ],
    });
    // Load a *different* account so `other` isn't the in-memory one.
    await service.loadFor(accountNamed('fav-export-active'));
    final exported = await service.exportFor(other);
    expect(exported.single['id'], '9');
  });

  test('deleteFor wipes an account and clears the in-memory list', () async {
    final account = accountNamed('fav-delete');
    await service.loadFor(account);
    await service.toggle(const FavoriteItem(type: 'movie', id: '1', name: 'X'));

    await service.deleteFor(account);
    expect(service.items, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('favorites_v1_${account.key}'), isNull);
  });

  group('reorder', () {
    Future<void> seed(String user) async {
      final account = accountNamed(user);
      await service.loadFor(account);
      for (final f in const [
        FavoriteItem(type: 'movie', id: 'm1', name: 'M1'),
        FavoriteItem(type: 'series', id: 's1', name: 'S1'),
        FavoriteItem(type: 'movie', id: 'm2', name: 'M2'),
        FavoriteItem(type: 'movie', id: 'm3', name: 'M3'),
      ]) {
        await service.toggle(f);
      }
    }

    List<String> idsOfType(String type) =>
        service.items.where((i) => i.type == type).map((i) => i.id).toList();

    test('moves an item within its type', () async {
      await seed('fav-reorder-basic');
      // Move m1 (index 0 among movies) to the end (index 2 post-removal).
      await service.reorder('movie', 0, 2);
      expect(idsOfType('movie'), ['m2', 'm3', 'm1']);
    });

    test('leaves other types untouched and in their slots', () async {
      await seed('fav-reorder-other');
      await service.reorder('movie', 2, 0); // m3 to front of movies
      expect(idsOfType('movie'), ['m3', 'm1', 'm2']);
      expect(idsOfType('series'), ['s1']); // unaffected
      // The series item keeps its absolute position (still 2nd overall, right
      // after the first movie slot).
      expect(service.items.map((i) => i.id).toList(),
          ['m3', 's1', 'm1', 'm2']);
    });

    test('persists the new order', () async {
      final account = accountNamed('fav-reorder-persist');
      await service.loadFor(account);
      await service.toggle(const FavoriteItem(type: 'movie', id: 'a', name: 'A'));
      await service.toggle(const FavoriteItem(type: 'movie', id: 'b', name: 'B'));
      await service.reorder('movie', 1, 0); // B before A

      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getStringList('favorites_v1_${account.key}')!;
      final ids = stored
          .map((s) => (jsonDecode(s) as Map)['id'] as String)
          .toList();
      expect(ids, ['b', 'a']);
    });

    test('out-of-range or no-op indices do nothing', () async {
      await seed('fav-reorder-noop');
      await service.reorder('movie', 5, 0); // from out of range
      expect(idsOfType('movie'), ['m1', 'm2', 'm3']);
      await service.reorder('movie', 1, 1); // same slot
      expect(idsOfType('movie'), ['m1', 'm2', 'm3']);
    });
  });
}
