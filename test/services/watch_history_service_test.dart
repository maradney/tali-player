import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/db/catalog_database.dart';
import 'package:iptv_player/data/models/catalog_row.dart';
import 'package:iptv_player/data/models/search_result.dart' show ContentType;
import 'package:iptv_player/data/models/watch_history_entry.dart';
import 'package:iptv_player/data/services/watch_history_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/test_support.dart';

WatchHistoryEntry _entry(String type, String id, {DateTime? at}) => WatchHistoryEntry(
      type: type,
      id: id,
      name: '$type-$id',
      watchedAt: at ?? DateTime.now(),
    );

WatchHistoryEntry _episode(String id, String seriesId, {DateTime? at}) =>
    WatchHistoryEntry(
      type: 'episode',
      id: id,
      name: 'Series $seriesId',
      seriesId: seriesId,
      watchedAt: at ?? DateTime.now(),
    );

void main() {
  final service = WatchHistoryService.instance;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  test('record prepends newest-first', () async {
    await service.loadFor(accountNamed('wh-order'));
    await service.record(_entry('movie', '1'));
    await service.record(_entry('movie', '2'));
    expect(service.entries.map((e) => e.id), ['2', '1']);
  });

  test('rewatching moves an existing entry back to the top', () async {
    await service.loadFor(accountNamed('wh-dedupe'));
    await service.record(_entry('movie', '1'));
    await service.record(_entry('movie', '2'));
    await service.record(_entry('movie', '1')); // rewatch
    expect(service.entries.map((e) => e.id), ['1', '2']);
    expect(service.entries, hasLength(2));
  });

  test('caps the log at 300 entries, dropping the oldest', () async {
    await service.loadFor(accountNamed('wh-cap'));
    for (var i = 0; i < 305; i++) {
      await service.record(_entry('movie', 'm$i'));
    }
    expect(service.entries, hasLength(300));
    expect(service.entries.first.id, 'm304'); // newest kept
    expect(service.entries.last.id, 'm5'); // m0..m4 dropped
    expect(service.entries.any((e) => e.id == 'm0'), isFalse);
  });

  test('remove deletes a single entry by key', () async {
    await service.loadFor(accountNamed('wh-remove'));
    await service.record(_entry('movie', '1'));
    await service.record(_entry('episode', '9'));
    await service.remove('movie:1');
    expect(service.entries.map((e) => e.key), ['episode:9']);
  });

  test('removeSeries clears every episode of one show, leaving others', () async {
    await service.loadFor(accountNamed('wh-remove-series'));
    await service.record(_episode('s5e1', '5'));
    await service.record(_episode('s5e2', '5'));
    await service.record(_episode('s7e1', '7'));
    await service.record(_entry('movie', '1'));

    await service.removeSeries('5');

    // Both episodes of series 5 are gone; the other show and the movie stay.
    expect(service.entries.map((e) => e.key),
        containsAll(<String>['episode:s7e1', 'movie:1']));
    expect(service.entries.any((e) => e.seriesId == '5'), isFalse);
    expect(service.entries, hasLength(2));
  });

  test('lastLiveEntry returns the most recent live channel, or null', () async {
    await service.loadFor(accountNamed('wh-lastlive'));
    expect(service.lastLiveEntry, isNull);

    await service.record(_entry('live', '100', at: DateTime(2024, 1, 1)));
    await service.record(_entry('movie', '1'));
    await service.record(_entry('live', '200')); // most recent live

    expect(service.lastLiveEntry?.id, '200');
  });

  test('clear empties the whole log', () async {
    await service.loadFor(accountNamed('wh-clear'));
    await service.record(_entry('movie', '1'));
    await service.clear();
    expect(service.entries, isEmpty);
  });

  test('loadFor backfills missing posters from the offline catalog', () async {
    await initDbEnvironment();
    final account = accountNamed('wh-backfill');

    // The catalog knows the series cover and the movie poster.
    await CatalogDatabase.instance
        .replaceTypeItems(account.key, ContentType.series, [
      CatalogRow(
        accountKey: account.key,
        type: ContentType.series,
        id: 's1',
        name: 'Dark',
        categoryId: '5',
        imageUrl: 'http://host/dark.jpg',
      ),
    ]);
    await CatalogDatabase.instance
        .replaceTypeItems(account.key, ContentType.movie, [
      CatalogRow(
        accountKey: account.key,
        type: ContentType.movie,
        id: 'm1',
        name: 'Dune',
        categoryId: '4',
        imageUrl: 'http://host/dune.jpg',
      ),
    ]);

    // History persisted before the fix: entries with no imageUrl.
    SharedPreferences.setMockInitialValues({
      'watch_history_v1_${account.key}': [
        jsonEncode(_episode('e1', 's1').toJson()),
        jsonEncode(_entry('movie', 'm1').toJson()),
        jsonEncode(_entry('movie', 'unknown').toJson()), // not in the catalog
      ],
    });

    await service.loadFor(account);
    await service.lastPosterBackfill; // normally fire-and-forget

    String? imageOf(String key) =>
        service.entries.firstWhere((e) => e.key == key).imageUrl;
    expect(imageOf('episode:e1'), 'http://host/dark.jpg');
    expect(imageOf('movie:m1'), 'http://host/dune.jpg');
    expect(imageOf('movie:unknown'), isNull);

    // Healed posters are persisted, not just in memory.
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('watch_history_v1_${account.key}')!;
    expect(raw.join(), contains('dark.jpg'));
  });

  test('deleteFor wipes an account and clears memory', () async {
    final account = accountNamed('wh-delete');
    await service.loadFor(account);
    await service.record(_entry('movie', '1'));
    await service.deleteFor(account);
    expect(service.entries, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('watch_history_v1_${account.key}'), isNull);
  });
}
