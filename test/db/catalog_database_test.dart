import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/db/catalog_database.dart';
import 'package:iptv_player/data/models/catalog_row.dart';
import 'package:iptv_player/data/models/search_result.dart';

import '../support/test_support.dart';

CatalogRow _row(
  String accountKey,
  ContentType type,
  String id,
  String name,
  String categoryId, {
  Map<String, dynamic> extra = const {},
}) =>
    CatalogRow(
      accountKey: accountKey,
      type: type,
      id: id,
      name: name,
      categoryId: categoryId,
      extra: extra,
    );

void main() {
  final db = CatalogDatabase.instance;

  setUpAll(() async {
    await initDbEnvironment();
  });

  group('catalog items + search', () {
    const key = 'acct-search';

    setUp(() async {
      await db.replaceTypeItems(key, ContentType.movie, [
        _row(key, ContentType.movie, '1', 'The Matrix', '4'),
        _row(key, ContentType.movie, '2', 'Matrix Reloaded', '4'),
        _row(key, ContentType.movie, '3', 'Inception', '5'),
      ]);
    });

    test('search matches a case-insensitive name substring', () async {
      final rows = await db.search(key, 'matrix');
      expect(rows.map((r) => r.id).toSet(), {'1', '2'});
    });

    test('replaceTypeItems fully replaces the prior set for that type', () async {
      await db.replaceTypeItems(key, ContentType.movie, [
        _row(key, ContentType.movie, '9', 'Only One', '4'),
      ]);
      final rows = await db.search(key, '');
      expect(rows.map((r) => r.id), ['9']);
    });

    test('searchCount matches search cardinality', () async {
      expect(await db.searchCount(key, 'matrix'), 2);
      expect(await db.searchCount(key, 'zzz'), 0);
    });

    test('searchCount excludes titles in a locked category', () async {
      // Both Matrix films sit in category '4'; locking it zeroes the count so
      // the tab badge matches the (filtered) result list.
      expect(await db.searchCount(key, 'matrix'), 2);
      expect(
          await db.searchCount(key, 'matrix', lockedCategoryKeys: {'movie:4'}),
          0);
      // A blank query counts every title; locking '4' leaves only Inception
      // (category '5'). A lock on another type/category doesn't touch movies.
      expect(await db.searchCount(key, '', lockedCategoryKeys: {'movie:4'}), 1);
      expect(
          await db.searchCount(key, '', lockedCategoryKeys: {'live:4'}), 3);
    });

    test('searchCount with a kids allowlist counts ONLY allowed categories',
        () async {
      // Matrix films are in '4', Inception in '5'. Allowlist = {'movie:5'}
      // means only Inception is visible.
      expect(await db.searchCount(key, '', allowedCategoryKeys: {'movie:5'}), 1);
      expect(
          await db.searchCount(key, 'matrix', allowedCategoryKeys: {'movie:5'}),
          0);
      expect(
          await db.searchCount(key, 'matrix', allowedCategoryKeys: {'movie:4'}),
          2);
      // An empty allowlist (default-deny) => nothing visible.
      expect(await db.searchCount(key, '', allowedCategoryKeys: <String>{}), 0);
      // null (filter disabled) => no restriction, counts everything.
      expect(await db.searchCount(key, '', allowedCategoryKeys: null), 3);
    });

    test('countFor counts all rows, optionally by type', () async {
      expect(await db.countFor(key), 3);
      expect(await db.countFor(key, type: ContentType.movie), 3);
      expect(await db.countFor(key, type: ContentType.live), 0);
    });

    test('itemsInCategory returns only that category, name-sorted', () async {
      final rows =
          await db.itemsInCategory(key, ContentType.movie, '4');
      expect(rows.map((r) => r.name), ['Matrix Reloaded', 'The Matrix']);
      expect(await db.itemsInCategory(key, ContentType.movie, 'nope'),
          isEmpty);
      expect(
          await db.itemsInCategory(key, ContentType.live, '4'), isEmpty,
          reason: 'scoped to the requested type');
    });

    test('categoryIdsForType lists distinct ids, case-insensitively sorted',
        () async {
      expect(await db.categoryIdsForType(key, ContentType.movie), ['4', '5']);
      expect(await db.categoryIdsForType(key, ContentType.series), isEmpty);
    });
  });

  group('categoryIndexFor', () {
    test('maps type:id -> categoryId, skipping empty categories', () async {
      const key = 'acct-index';
      await db.replaceTypeItems(key, ContentType.live, [
        _row(key, ContentType.live, '10', 'A', '3'),
        _row(key, ContentType.live, '11', 'B', ''), // empty -> skipped
      ]);
      await db.replaceTypeItems(key, ContentType.movie, [
        _row(key, ContentType.movie, '20', 'C', '7'),
      ]);

      final index = await db.categoryIndexFor(key);
      expect(index['live:10'], '3');
      expect(index['movie:20'], '7');
      expect(index.containsKey('live:11'), isFalse);
    });
  });

  group('sync metadata', () {
    test('typeSyncedAt round-trips a timestamp', () async {
      const key = 'acct-sync';
      expect(await db.typeSyncedAt(key, ContentType.series), isNull);
      final when = DateTime.fromMillisecondsSinceEpoch(1700000000000);
      await db.setTypeSyncedAt(key, ContentType.series, when);
      expect(await db.typeSyncedAt(key, ContentType.series), when);
    });
  });

  group('detail cache', () {
    test('returns a fresh entry and null once expired', () async {
      const key = 'acct-detail';
      await db.saveDetail(key, 'movie', '1', {'info': {'plot': 'p'}});
      final fresh = await db.getCachedDetail(key, 'movie', '1',
          maxAge: const Duration(days: 1));
      expect(fresh, isNotNull);
      expect(fresh!['info'], {'plot': 'p'});

      final expired = await db.getCachedDetail(key, 'movie', '1',
          maxAge: const Duration(seconds: -1));
      expect(expired, isNull);
    });
  });

  group('epg cache', () {
    test('separates short and full sources, honors max age', () async {
      const key = 'acct-epg';
      await db.saveEpg(key, 's1', 'short', [
        {'title': 'now'},
      ]);
      final short = await db.getCachedEpg(key, 's1', 'short',
          maxAge: const Duration(minutes: 10));
      expect(short, hasLength(1));
      // Different source slot -> independent, still empty.
      expect(
        await db.getCachedEpg(key, 's1', 'full', maxAge: const Duration(minutes: 15)),
        isNull,
      );
    });
  });

  group('deleteForAccount', () {
    test('wipes catalog, sync meta, and caches for that account only', () async {
      const key = 'acct-wipe';
      const other = 'acct-keep';
      await db.replaceTypeItems(key, ContentType.movie, [
        _row(key, ContentType.movie, '1', 'X', '1'),
      ]);
      await db.replaceTypeItems(other, ContentType.movie, [
        _row(other, ContentType.movie, '1', 'Y', '1'),
      ]);

      await db.deleteForAccount(key);
      expect(await db.countFor(key), 0);
      expect(await db.countFor(other), 1);
    });
  });

  group('recentlyAdded', () {
    const key = 'acct-recent';

    setUp(() async {
      await db.deleteForAccount(key);
      // Three movies + a series with distinct added_at, plus one undated
      // movie and a live channel that must never appear.
      await db.replaceTypeItems(key, ContentType.movie, [
        const CatalogRow(
            accountKey: key,
            type: ContentType.movie,
            id: 'm-old',
            name: 'Old Movie',
            categoryId: '1',
            addedAt: 1000),
        const CatalogRow(
            accountKey: key,
            type: ContentType.movie,
            id: 'm-new',
            name: 'New Movie',
            categoryId: '1',
            addedAt: 3000),
        const CatalogRow(
            accountKey: key,
            type: ContentType.movie,
            id: 'm-undated',
            name: 'Undated Movie',
            categoryId: '1'),
      ]);
      await db.replaceTypeItems(key, ContentType.series, [
        const CatalogRow(
            accountKey: key,
            type: ContentType.series,
            id: 's-mid',
            name: 'Mid Series',
            categoryId: '2',
            addedAt: 2000),
      ]);
      await db.replaceTypeItems(key, ContentType.live, [
        const CatalogRow(
            accountKey: key,
            type: ContentType.live,
            id: 'l1',
            name: 'A Channel',
            categoryId: '3',
            addedAt: 9999),
      ]);
    });

    test('All returns movies+series newest-first, excluding live + undated',
        () async {
      final rows = await db.recentlyAdded(key);
      expect(rows.map((r) => r.id), ['m-new', 's-mid', 'm-old']);
    });

    test('filters by type', () async {
      final rows = await db.recentlyAdded(key, type: ContentType.movie);
      expect(rows.map((r) => r.id), ['m-new', 'm-old']);
    });

    test('honors the limit', () async {
      final rows = await db.recentlyAdded(key, limit: 1);
      expect(rows.single.id, 'm-new');
    });

    test('added_at round-trips through the db', () async {
      final rows = await db.recentlyAdded(key, type: ContentType.series);
      expect(rows.single.addedAt, 2000);
    });
  });

  group('reassignAccountKey', () {
    test('re-keys a profile-migrated account, leaving others alone', () async {
      const oldKey = 'http://h:8080|bob';
      const newKey = 'default|http://h:8080|bob';
      const other = 'default|http://h:8080|carol';
      await db.replaceTypeItems(oldKey, ContentType.movie, [
        _row(oldKey, ContentType.movie, '1', 'Dune', '4'),
      ]);
      await db.replaceTypeItems(other, ContentType.movie, [
        _row(other, ContentType.movie, '1', 'Arrival', '4'),
      ]);

      await db.reassignAccountKey(oldKey, newKey);

      expect(await db.countFor(oldKey), 0);
      expect(await db.countFor(newKey), 1);
      expect(await db.countFor(other), 1); // untouched
      final rows = await db.search(newKey, 'dune');
      expect(rows.single.id, '1');
    });
  });

  group('enhanced search enrichment', () {
    const key = 'acct-enrich';

    setUp(() async {
      await db.deleteForAccount(key);
      await db.replaceTypeItems(key, ContentType.movie, [
        _row(key, ContentType.movie, '1', 'Inception', '4'),
        _row(key, ContentType.movie, '2', 'Interstellar', '4'),
      ]);
      await db.replaceTypeItems(key, ContentType.series, [
        _row(key, ContentType.series, '3', 'Dark', '5'),
      ]);
      // A live channel must never count toward enrichment.
      await db.replaceTypeItems(key, ContentType.live, [
        _row(key, ContentType.live, '9', 'News 24', '6'),
      ]);
    });

    test('rowsNeedingEnrichment returns only unenriched movies+series', () async {
      final pending = await db.rowsNeedingEnrichment(key);
      expect(pending.map((r) => r.id).toSet(), {'1', '2', '3'});
      expect(pending.every((r) => r.type != ContentType.live), isTrue);
    });

    test('saveEnrichment stamps a row so it drops out of the pending set',
        () async {
      await db.saveEnrichment(key, ContentType.movie, '1',
          cast: 'Leonardo DiCaprio', director: 'Christopher Nolan');
      final pending = await db.rowsNeedingEnrichment(key);
      expect(pending.map((r) => r.id).toSet(), {'2', '3'});
    });

    test('enrichmentProgress counts enriched vs total (movies+series only)',
        () async {
      var p = await db.enrichmentProgress(key);
      expect(p, (enriched: 0, total: 3));
      await db.saveEnrichment(key, ContentType.movie, '1', director: 'Nolan');
      p = await db.enrichmentProgress(key);
      expect(p, (enriched: 1, total: 3));
    });

    test('creditsFor returns a lowercased blob for enriched rows only',
        () async {
      await db.saveEnrichment(key, ContentType.movie, '1',
          cast: 'Leonardo DiCaprio', director: 'Christopher Nolan',
          genre: 'Sci-Fi');
      final credits = await db.creditsFor(key, ContentType.movie);
      expect(credits.keys, {'1'});
      expect(credits['1'], contains('nolan'));
      expect(credits['1'], contains('sci-fi'));
    });

    test('blank fields are normalized to null, not stored', () async {
      await db.saveEnrichment(key, ContentType.movie, '1',
          cast: '   ', director: 'Nolan', genre: '');
      final credits = await db.creditsFor(key, ContentType.movie);
      expect(credits['1'], 'nolan'); // only the non-blank field
    });

    test('search matches credits only when matchCredits is set', () async {
      await db.saveEnrichment(key, ContentType.movie, '1',
          director: 'Christopher Nolan');
      // Plain search is title-only: "nolan" is not a title.
      expect(await db.search(key, 'nolan'), isEmpty);
      // Enhanced search reaches the director.
      final rows = await db.search(key, 'nolan', matchCredits: true);
      expect(rows.single.id, '1');
      // searchCount mirrors it.
      expect(await db.searchCount(key, 'nolan'), 0);
      expect(await db.searchCount(key, 'nolan', matchCredits: true), 1);
    });

    test('captures year and backfills a rating the list lacked', () async {
      await db.saveEnrichment(key, ContentType.movie, '1',
          director: 'Nolan', year: 2010, rating: '8.8');
      final row = (await db.search(key, 'inception')).single;
      expect(row.year, 2010);
      // No list rating on this row, so the detail rating surfaces via extra.
      expect(row.toSearchResult().rating, '8.8');
    });

    test('detail rating never overrides a rating the list already gave',
        () async {
      // Reseed movie '2' with a list rating.
      await db.replaceTypeItems(key, ContentType.movie, [
        _row(key, ContentType.movie, '1', 'Inception', '4'),
        _row(key, ContentType.movie, '2', 'Interstellar', '4',
            extra: {'rating': '5.0'}),
      ]);
      await db.saveEnrichment(key, ContentType.movie, '2', rating: '9.0');
      final row = (await db.search(key, 'interstellar')).single;
      expect(row.toSearchResult().rating, '5.0');
    });

    test('enrichment survives a resync of the same type', () async {
      await db.saveEnrichment(key, ContentType.movie, '1',
          director: 'Christopher Nolan', year: 2010);
      // Resync: '1' still present (keeps credits), '2' gone, '99' new.
      await db.replaceTypeItems(key, ContentType.movie, [
        _row(key, ContentType.movie, '1', 'Inception', '4'),
        _row(key, ContentType.movie, '99', 'Tenet', '4'),
      ]);
      final kept = (await db.search(key, 'nolan', matchCredits: true)).single;
      expect(kept.id, '1');
      expect(kept.year, 2010); // year preserved too, not just credits
      // The new item is unenriched and back in the pending set.
      final pending = await db.rowsNeedingEnrichment(key);
      expect(pending.map((r) => r.id), contains('99'));
      expect(pending.map((r) => r.id), isNot(contains('1')));
    });

    test('clearEnrichment resets everything for the account', () async {
      await db.saveEnrichment(key, ContentType.movie, '1', director: 'Nolan');
      await db.clearEnrichment(key);
      expect((await db.enrichmentProgress(key)).enriched, 0);
      expect(await db.creditsFor(key, ContentType.movie), isEmpty);
      expect((await db.rowsNeedingEnrichment(key)).length, 3);
    });
  });

  group('genre browse (genreFacets + byGenre)', () {
    const key = 'acct-genre';

    setUp(() async {
      await db.replaceTypeItems(key, ContentType.movie, [
        _row(key, ContentType.movie, '1', 'Inception', '4'),
        _row(key, ContentType.movie, '2', 'Interstellar', '4'),
        _row(key, ContentType.movie, '3', 'Untagged', '4'),
      ]);
      await db.replaceTypeItems(key, ContentType.series, [
        _row(key, ContentType.series, '10', 'Dark', '5'),
      ]);
      // Multi-genre strings that should be tokenized and aggregated.
      await db.saveEnrichment(key, ContentType.movie, '1',
          genre: 'Action, Sci-Fi', year: 2010);
      await db.saveEnrichment(key, ContentType.movie, '2',
          genre: 'Sci-Fi | Drama', year: 2014);
      await db.saveEnrichment(key, ContentType.series, '10',
          genre: 'Sci-Fi, Thriller', year: 2017);
      // '3' stays unenriched (no genre) — must not appear in any facet.
    });

    test('genreFacets aggregates tokens across type, counted and sorted',
        () async {
      final facets = await db.genreFacets(key);
      // Sci-Fi is on all three enriched items; others once each.
      expect(facets.first, (genre: 'Sci-Fi', count: 3));
      final counts = {for (final f in facets) f.genre: f.count};
      expect(counts, {
        'Sci-Fi': 3,
        'Action': 1,
        'Drama': 1,
        'Thriller': 1,
      });
    });

    test('genreFacets can scope to one content type', () async {
      final movieFacets = await db.genreFacets(key, type: ContentType.movie);
      final counts = {for (final f in movieFacets) f.genre: f.count};
      expect(counts, {'Sci-Fi': 2, 'Action': 1, 'Drama': 1});
      expect(counts.containsKey('Thriller'), isFalse); // series-only genre
    });

    test('byGenre returns exact-token matches across categories and types',
        () async {
      final rows = await db.byGenre(key, 'Sci-Fi');
      expect(rows.map((r) => r.id).toSet(), {'1', '2', '10'});
      // Carries the enriched year through for the year filter.
      expect(rows.firstWhere((r) => r.id == '1').year, 2010);
    });

    test('byGenre does not substring-match a different genre', () async {
      // "Fi" is a substring of "Sci-Fi" but not a genre token of its own.
      expect(await db.byGenre(key, 'Fi'), isEmpty);
      expect((await db.byGenre(key, 'Drama')).map((r) => r.id), ['2']);
    });

    test('byGenre can scope to one content type', () async {
      final rows = await db.byGenre(key, 'Sci-Fi', type: ContentType.series);
      expect(rows.map((r) => r.id), ['10']);
    });

    test('genreFacets excludes titles in a locked category', () async {
      // Movies 1 & 2 sit in category '4'; locking it should drop them from the
      // facets, leaving only the series (category '5') genres.
      final facets =
          await db.genreFacets(key, lockedCategoryKeys: {'movie:4'});
      final counts = {for (final f in facets) f.genre: f.count};
      expect(counts, {'Sci-Fi': 1, 'Thriller': 1});
    });

    test('byGenre honors a result limit (applied to the LIKE prefilter)',
        () async {
      // Sci-Fi candidates by name: Dark(10), Inception(1), Interstellar(2).
      final rows = await db.byGenre(key, 'Sci-Fi', limit: 1);
      expect(rows.map((r) => r.id), ['10']);
    });

    test('genreFacets with a kids allowlist counts ONLY allowed categories',
        () async {
      // Allow only the series category ('5'): the movies (category '4') and
      // their genres must not appear on the landing.
      final facets =
          await db.genreFacets(key, allowedCategoryKeys: {'series:5'});
      final counts = {for (final f in facets) f.genre: f.count};
      expect(counts, {'Sci-Fi': 1, 'Thriller': 1});

      // An empty allowlist hides every genre.
      expect(await db.genreFacets(key, allowedCategoryKeys: <String>{}),
          isEmpty);
      // null => no restriction (all four genres present).
      expect(
          (await db.genreFacets(key, allowedCategoryKeys: null)).length, 4);
    });
  });

  group('toSearchResult integration', () {
    test('rows fetched from the db rebuild typed objects', () async {
      const key = 'acct-tosearch';
      await db.replaceTypeItems(key, ContentType.movie, [
        _row(key, ContentType.movie, '1', 'The Matrix', '4',
            extra: {'containerExtension': 'mkv', 'rating': '7.4'}),
      ]);
      final rows = await db.search(key, 'matrix');
      final result = rows.single.toSearchResult();
      expect(result.type, ContentType.movie);
      expect(result.rating, '7.4');
    });
  });
}
