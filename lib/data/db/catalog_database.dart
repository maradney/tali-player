import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/catalog_row.dart';
import '../models/genre_util.dart';
import '../models/search_result.dart';
import '../sources/xmltv_parser.dart';

/// Local persistent search index. This is what makes search feel instant
/// and "always current" without a visible indexing step - the catalog
/// lives on disk and is queried directly (no network call), while
/// CatalogSyncService keeps it refreshed in the background.
class CatalogDatabase {
  CatalogDatabase._();
  static final CatalogDatabase instance = CatalogDatabase._();

  Database? _db;
  static bool _factoryInitialized = false;

  Future<Database> get _database async {
    if (_db != null) return _db!;
    _initFactoryIfNeeded();
    final dir = await getApplicationSupportDirectory();
    final path = p.join(dir.path, 'catalog.db');
    _db = await openDatabase(
      path,
      version: 8,
      onCreate: (db, version) async {
        await db.execute(_createCatalogItemsSql);
        await db.execute(_createCatalogNameIndexSql);
        await db.execute(_createCatalogAddedIndexSql);
        await db.execute(_createCatalogEnrichedIndexSql);
        // Keyed per (account, content type) rather than per account, so
        // each of Live/Movies/Series can finish and become searchable
        // independently instead of all-or-nothing.
        await db.execute(_createSyncMetaSql);
        await db.execute(_createDetailCacheSql);
        await db.execute(_createEpgCacheSql);
        await db.execute(_createEpgProgrammesSql);
        await db.execute(_createEpgProgrammesIndexSql);
      },
      // Local cache only, but additive rather than destructive - each
      // table is created only if it's missing, so bumping the version to
      // add a new table (e.g. detail_cache) never wipes the indexed
      // catalog/sync state that's already on disk. A resync from zero
      // used to happen on every version bump, which defeated the point of
      // caching - see catalog_sync_service.dart's syncIfNeeded.
      //
      // CAUTION: this pattern only handles new *tables*. CREATE TABLE IF
      // NOT EXISTS is a no-op for an existing table that gained a column,
      // so adding a column to any table later needs an explicit
      // `if (oldVersion < N) ALTER TABLE ... ADD COLUMN ...` step here -
      // without one, upgraded installs will crash on the missing column
      // while fresh installs work fine.
      onUpgrade: (db, oldVersion, newVersion) async {
        await db.execute(_createCatalogItemsSql.replaceFirst(
            'CREATE TABLE', 'CREATE TABLE IF NOT EXISTS'));
        await db.execute(_createCatalogNameIndexSql.replaceFirst(
            'CREATE INDEX', 'CREATE INDEX IF NOT EXISTS'));
        await db.execute(_createSyncMetaSql.replaceFirst(
            'CREATE TABLE', 'CREATE TABLE IF NOT EXISTS'));
        await db.execute(_createDetailCacheSql.replaceFirst(
            'CREATE TABLE', 'CREATE TABLE IF NOT EXISTS'));
        await db.execute(_createEpgCacheSql.replaceFirst(
            'CREATE TABLE', 'CREATE TABLE IF NOT EXISTS'));
        // v5: catalog_items gained the added_at column (+ its index). Unlike a
        // new table, a new column needs an explicit ALTER on existing installs
        // - CREATE TABLE IF NOT EXISTS above is a no-op for the existing table.
        // Existing rows get NULL added_at until the next background resync
        // repopulates them from the panel.
        if (oldVersion < 5) {
          await db.execute(
              'ALTER TABLE catalog_items ADD COLUMN added_at INTEGER');
          await db.execute(_createCatalogAddedIndexSql.replaceFirst(
              'CREATE INDEX', 'CREATE INDEX IF NOT EXISTS'));
        }
        // v6: enhanced search — catalog_items gained cast/director/genre text
        // plus enriched_at (when the per-item detail crawl last filled them in;
        // NULL = not yet enriched, which is what the background pass looks for).
        // Same ALTER-per-column rule as v5: CREATE TABLE IF NOT EXISTS above is
        // a no-op for the existing table, so existing installs need explicit
        // ADD COLUMNs here or they'd crash on the missing columns.
        if (oldVersion < 6) {
          await db.execute(
              'ALTER TABLE catalog_items ADD COLUMN cast_names TEXT');
          await db
              .execute('ALTER TABLE catalog_items ADD COLUMN director TEXT');
          await db.execute('ALTER TABLE catalog_items ADD COLUMN genre TEXT');
          await db.execute(
              'ALTER TABLE catalog_items ADD COLUMN enriched_at INTEGER');
          await db.execute(_createCatalogEnrichedIndexSql.replaceFirst(
              'CREATE INDEX', 'CREATE INDEX IF NOT EXISTS'));
        }
        // v7: enrichment also captures release year (list responses lack it)
        // and a detail-sourced rating used to backfill items the list left
        // unrated. Both are enrichment-owned columns like the v6 set.
        if (oldVersion < 7) {
          await db
              .execute('ALTER TABLE catalog_items ADD COLUMN year INTEGER');
          await db.execute(
              'ALTER TABLE catalog_items ADD COLUMN detail_rating TEXT');
        }
        // v8: XMLTV EPG for M3U playlists — a new table, so the additive
        // CREATE TABLE IF NOT EXISTS pattern is enough (no ALTER needed).
        if (oldVersion < 8) {
          await db.execute(_createEpgProgrammesSql.replaceFirst(
              'CREATE TABLE', 'CREATE TABLE IF NOT EXISTS'));
          await db.execute(_createEpgProgrammesIndexSql.replaceFirst(
              'CREATE INDEX', 'CREATE INDEX IF NOT EXISTS'));
        }
      },
    );
    return _db!;
  }

  // cast_names/director/genre + enriched_at are filled in lazily by the
  // optional enhanced-search crawl (CatalogEnrichmentService); they're NULL on
  // a plain sync. `cast` is a SQL keyword, hence the cast_names column name.
  static const _createCatalogItemsSql = '''
    CREATE TABLE catalog_items (
      account_key TEXT NOT NULL,
      type TEXT NOT NULL,
      id TEXT NOT NULL,
      name TEXT NOT NULL,
      image_url TEXT,
      category_id TEXT,
      extra TEXT,
      added_at INTEGER,
      cast_names TEXT,
      director TEXT,
      genre TEXT,
      year INTEGER,
      detail_rating TEXT,
      enriched_at INTEGER,
      PRIMARY KEY (account_key, type, id)
    )
  ''';

  static const _createCatalogNameIndexSql =
      'CREATE INDEX idx_catalog_name ON catalog_items(account_key, name COLLATE NOCASE)';

  // Backs the Recently Added view's "ORDER BY added_at DESC" per account+type.
  static const _createCatalogAddedIndexSql =
      'CREATE INDEX idx_catalog_added ON catalog_items(account_key, type, added_at)';

  // Speeds the enrichment crawl's "which rows still need detail?" scan and its
  // progress counts (enriched vs total), per account+type.
  static const _createCatalogEnrichedIndexSql =
      'CREATE INDEX idx_catalog_enriched ON catalog_items(account_key, type, enriched_at)';

  static const _createSyncMetaSql = '''
    CREATE TABLE sync_meta (
      account_key TEXT NOT NULL,
      type TEXT NOT NULL,
      last_synced_at INTEGER,
      PRIMARY KEY (account_key, type)
    )
  ''';

  // Caches the raw get_vod_info/get_series_info API response for one item -
  // plot/cast/director/genre/seasons don't change often, so re-showing a
  // detail screen you've already opened can skip the network round trip.
  static const _createDetailCacheSql = '''
    CREATE TABLE detail_cache (
      account_key TEXT NOT NULL,
      type TEXT NOT NULL,
      id TEXT NOT NULL,
      json TEXT NOT NULL,
      cached_at INTEGER NOT NULL,
      PRIMARY KEY (account_key, type, id)
    )
  ''';

  /// Cached raw API response for one movie/series detail call, or null if
  /// there's no entry or it's older than [maxAge].
  Future<Map<String, dynamic>?> getCachedDetail(
    String accountKey,
    String type,
    String id, {
    required Duration maxAge,
  }) async {
    final db = await _database;
    final rows = await db.query(
      'detail_cache',
      where: 'account_key = ? AND type = ? AND id = ?',
      whereArgs: [accountKey, type, id],
    );
    if (rows.isEmpty) return null;
    final cachedAt =
        DateTime.fromMillisecondsSinceEpoch(rows.first['cached_at'] as int);
    if (DateTime.now().difference(cachedAt) > maxAge) return null;
    return jsonDecode(rows.first['json'] as String) as Map<String, dynamic>;
  }

  Future<void> saveDetail(
    String accountKey,
    String type,
    String id,
    Map<String, dynamic> json,
  ) async {
    final db = await _database;
    await db.insert(
      'detail_cache',
      {
        'account_key': accountKey,
        'type': type,
        'id': id,
        'json': jsonEncode(json),
        'cached_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // Caches get_short_epg/get_simple_data_table responses per channel.
  // "source" keeps the two endpoints in separate slots (short = now/next,
  // full = the day-long listing the grid guide needs) since they have
  // different freshness needs and shapes.
  static const _createEpgCacheSql = '''
    CREATE TABLE epg_cache (
      account_key TEXT NOT NULL,
      stream_id TEXT NOT NULL,
      source TEXT NOT NULL,
      json TEXT NOT NULL,
      cached_at INTEGER NOT NULL,
      PRIMARY KEY (account_key, stream_id, source)
    )
  ''';

  // XMLTV EPG for M3U playlists: one row per programme, keyed by the channel's
  // tvg-id (channel_id). Stored as individual rows (not a per-channel JSON blob
  // like epg_cache) so now/next and grid windows can be queried by time.
  static const _createEpgProgrammesSql = '''
    CREATE TABLE epg_programmes (
      account_key TEXT NOT NULL,
      channel_id TEXT NOT NULL,
      start_ms INTEGER NOT NULL,
      stop_ms INTEGER NOT NULL,
      title TEXT,
      description TEXT
    )
  ''';

  static const _createEpgProgrammesIndexSql =
      'CREATE INDEX idx_epg_programmes ON epg_programmes(account_key, channel_id, start_ms)';

  /// Cached EPG listing for one channel, or null if there's no entry or
  /// it's older than [maxAge].
  Future<List<Map<String, dynamic>>?> getCachedEpg(
    String accountKey,
    String streamId,
    String source, {
    required Duration maxAge,
  }) async {
    final db = await _database;
    final rows = await db.query(
      'epg_cache',
      where: 'account_key = ? AND stream_id = ? AND source = ?',
      whereArgs: [accountKey, streamId, source],
    );
    if (rows.isEmpty) return null;
    final cachedAt =
        DateTime.fromMillisecondsSinceEpoch(rows.first['cached_at'] as int);
    if (DateTime.now().difference(cachedAt) > maxAge) return null;
    return (jsonDecode(rows.first['json'] as String) as List)
        .cast<Map<String, dynamic>>();
  }

  Future<void> saveEpg(
    String accountKey,
    String streamId,
    String source,
    List<Map<String, dynamic>> programs,
  ) async {
    final db = await _database;
    await db.insert(
      'epg_cache',
      {
        'account_key': accountKey,
        'stream_id': streamId,
        'source': source,
        'json': jsonEncode(programs),
        'cached_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// sqflite works natively on Android/iOS. On Windows/Linux it needs the
  /// FFI-based factory instead - this picks the right one automatically
  /// so the rest of the app doesn't need to care which platform it's on.
  void _initFactoryIfNeeded() {
    if (_factoryInitialized) return;
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    _factoryInitialized = true;
  }

  /// Full replace of one account's items of one content type, inside a
  /// transaction - simpler and safer than diffing row-by-row, and plenty
  /// fast for a personal-use catalog size (thousands, not millions, of
  /// rows). Scoped to a single type so Live/Movies/Series can each land
  /// in the index as soon as that type finishes syncing, rather than
  /// waiting for the whole catalog.
  Future<void> replaceTypeItems(
    String accountKey,
    ContentType type,
    List<CatalogRow> rows,
  ) async {
    final db = await _database;
    await db.transaction((txn) async {
      // Enhanced-search enrichment (cast/director/genre) is expensive to fetch,
      // so preserve it across this wipe: an item still present after the resync
      // keeps its credits rather than needing to be re-crawled. Items dropped by
      // the panel fall away; genuinely new items come back with NULL enriched_at
      // and get picked up by the next enrichment pass. CatalogRow deliberately
      // doesn't carry these fields (a plain sync would null them out), so we
      // snapshot straight from the table and re-apply by id.
      final existing = await txn.query(
        'catalog_items',
        columns: [
          'id',
          'cast_names',
          'director',
          'genre',
          'year',
          'detail_rating',
          'enriched_at',
        ],
        where: 'account_key = ? AND type = ? AND enriched_at IS NOT NULL',
        whereArgs: [accountKey, type.name],
      );
      final enrichment = {for (final r in existing) r['id'] as String: r};

      await txn.delete(
        'catalog_items',
        where: 'account_key = ? AND type = ?',
        whereArgs: [accountKey, type.name],
      );
      final batch = txn.batch();
      for (final row in rows) {
        batch.insert(
          'catalog_items',
          row.toDbMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);

      if (enrichment.isEmpty) return;
      final restore = txn.batch();
      for (final row in rows) {
        final e = enrichment[row.id];
        if (e == null) continue;
        restore.update(
          'catalog_items',
          {
            'cast_names': e['cast_names'],
            'director': e['director'],
            'genre': e['genre'],
            'year': e['year'],
            'detail_rating': e['detail_rating'],
            'enriched_at': e['enriched_at'],
          },
          where: 'account_key = ? AND type = ? AND id = ?',
          whereArgs: [accountKey, type.name, row.id],
        );
      }
      await restore.commit(noResult: true);
    });
  }

  /// Replaces the rows of just the categories listed in [categoryIds], leaving
  /// every other category of this type exactly as it was.
  ///
  /// [replaceTypeItems] is all-or-nothing across a whole content type, which
  /// forces an impossible choice when a sync only partly succeeds: write, and
  /// delete the rows of categories the panel merely failed to re-serve; or skip
  /// the write, and throw away everything that did arrive. A real sync failed 6
  /// of 44 categories and the second choice discarded the other 38.
  ///
  /// Scoping the delete to the categories actually fetched avoids both. It also
  /// means coverage accumulates: if a different handful fails each run, the
  /// union of what is stored grows instead of restarting.
  ///
  /// Note this cannot prune a category the panel has *dropped* — it is not in
  /// [categoryIds], so its rows stay. A later clean sweep through
  /// [replaceTypeItems] does that.
  Future<void> replaceCategoryItems(
    String accountKey,
    ContentType type,
    Set<String> categoryIds,
    List<CatalogRow> rows,
  ) async {
    if (categoryIds.isEmpty) return;
    final db = await _database;
    await db.transaction((txn) async {
      // Same enrichment-preserving dance as replaceTypeItems: snapshot the
      // expensive cast/director/genre columns before the delete and re-apply
      // them to the rows that come back. Snapshotting the whole type rather
      // than just these categories costs one wider read and keeps the two
      // methods honest about doing the same thing.
      final existing = await txn.query(
        'catalog_items',
        columns: [
          'id',
          'cast_names',
          'director',
          'genre',
          'year',
          'detail_rating',
          'enriched_at',
        ],
        where: 'account_key = ? AND type = ? AND enriched_at IS NOT NULL',
        whereArgs: [accountKey, type.name],
      );
      final enrichment = {for (final r in existing) r['id'] as String: r};

      // Chunked: SQLite caps the number of bound variables per statement, and
      // a panel is free to have more categories than that cap.
      const idsPerStatement = 400;
      final ids = categoryIds.toList();
      for (var i = 0; i < ids.length; i += idsPerStatement) {
        final part = ids.skip(i).take(idsPerStatement).toList();
        final placeholders = List.filled(part.length, '?').join(',');
        await txn.delete(
          'catalog_items',
          where: 'account_key = ? AND type = ? '
              'AND category_id IN ($placeholders)',
          whereArgs: [accountKey, type.name, ...part],
        );
      }

      final batch = txn.batch();
      for (final row in rows) {
        batch.insert(
          'catalog_items',
          row.toDbMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);

      if (enrichment.isEmpty) return;
      final restore = txn.batch();
      for (final row in rows) {
        final e = enrichment[row.id];
        if (e == null) continue;
        restore.update(
          'catalog_items',
          {
            'cast_names': e['cast_names'],
            'director': e['director'],
            'genre': e['genre'],
            'year': e['year'],
            'detail_rating': e['detail_rating'],
            'enriched_at': e['enriched_at'],
          },
          where: 'account_key = ? AND type = ? AND id = ?',
          whereArgs: [accountKey, type.name, row.id],
        );
      }
      await restore.commit(noResult: true);
    });
  }

  /// Movies/series that haven't been enriched yet (NULL enriched_at), for the
  /// enhanced-search crawl. Live is excluded — channels have no cast/director.
  /// [limit] bounds a single batch so the crawl can checkpoint between chunks.
  Future<List<CatalogRow>> rowsNeedingEnrichment(
    String accountKey, {
    int? limit,
  }) async {
    final db = await _database;
    final rows = await db.query(
      'catalog_items',
      where: "account_key = ? AND enriched_at IS NULL "
          "AND type IN ('${ContentType.movie.name}', '${ContentType.series.name}')",
      whereArgs: [accountKey],
      limit: limit,
    );
    return rows.map(CatalogRow.fromDbMap).toList();
  }

  /// Stores one item's fetched credits (plus release year and a detail-sourced
  /// rating) and stamps it enriched so the crawl skips it next time. Empty
  /// strings are normalized to NULL so blank fields don't masquerade as data
  /// (or match a search for ""). [year]/[rating] are captured from the same
  /// detail response and passed through untouched when null.
  Future<void> saveEnrichment(
    String accountKey,
    ContentType type,
    String id, {
    String? cast,
    String? director,
    String? genre,
    int? year,
    String? rating,
  }) async {
    String? clean(String? s) => (s != null && s.trim().isNotEmpty) ? s.trim() : null;
    final db = await _database;
    await db.update(
      'catalog_items',
      {
        'cast_names': clean(cast),
        'director': clean(director),
        'genre': clean(genre),
        'year': year,
        'detail_rating': clean(rating),
        'enriched_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'account_key = ? AND type = ? AND id = ?',
      whereArgs: [accountKey, type.name, id],
    );
  }

  /// Clears every item's credits + enriched stamp for an account, so the next
  /// crawl re-fetches from scratch. Backs the Settings "Rebuild" action.
  Future<void> clearEnrichment(String accountKey) async {
    final db = await _database;
    await db.update(
      'catalog_items',
      {
        'cast_names': null,
        'director': null,
        'genre': null,
        'year': null,
        'detail_rating': null,
        'enriched_at': null,
      },
      where: 'account_key = ?',
      whereArgs: [accountKey],
    );
  }

  /// How many movies/series have been enriched vs. the total — drives the
  /// Settings progress line ("Enhanced 320 / 4,180").
  Future<({int enriched, int total})> enrichmentProgress(
      String accountKey) async {
    final db = await _database;
    const scope = "account_key = ? AND type IN ('movie', 'series')";
    final totalRes = await db
        .rawQuery('SELECT COUNT(*) c FROM catalog_items WHERE $scope', [accountKey]);
    final enrichedRes = await db.rawQuery(
        'SELECT COUNT(*) c FROM catalog_items WHERE $scope AND enriched_at IS NOT NULL',
        [accountKey]);
    return (
      enriched: Sqflite.firstIntValue(enrichedRes) ?? 0,
      total: Sqflite.firstIntValue(totalRes) ?? 0,
    );
  }

  /// A lowercased "cast director genre" blob per item id, for the given type
  /// (optionally one category), so the Movies/Series in-screen quick filter can
  /// match credits without a per-keystroke DB hit. Only enriched rows with at
  /// least one non-empty field are included.
  Future<Map<String, String>> creditsFor(
    String accountKey,
    ContentType type, {
    String? categoryId,
  }) async {
    final db = await _database;
    final where = StringBuffer(
        'account_key = ? AND type = ? AND enriched_at IS NOT NULL');
    final args = <Object?>[accountKey, type.name];
    if (categoryId != null) {
      where.write(' AND category_id = ?');
      args.add(categoryId);
    }
    final rows = await db.query(
      'catalog_items',
      columns: ['id', 'cast_names', 'director', 'genre'],
      where: where.toString(),
      whereArgs: args,
    );
    final map = <String, String>{};
    for (final r in rows) {
      final blob = [r['cast_names'], r['director'], r['genre']]
          .whereType<String>()
          .join(' ')
          .toLowerCase();
      if (blob.isNotEmpty) map[r['id'] as String] = blob;
    }
    return map;
  }

  /// Distinct genres across enriched movies/series (optionally one [type]),
  /// each with how many titles carry it — the facets for the global genre
  /// browse landing. Genre is free-text and often lists several at once, so
  /// each row's value is tokenized (see [splitGenres]) and counts aggregate
  /// case-insensitively. Only enriched rows contribute, so this is empty until
  /// the enhanced-search crawl has run. Sorted by count desc, then name.
  Future<List<({String genre, int count})>> genreFacets(
    String accountKey, {
    ContentType? type,
    Set<String> lockedCategoryKeys = const {},
    Set<String>? allowedCategoryKeys,
  }) async {
    final db = await _database;
    final where = StringBuffer(
        "account_key = ? AND enriched_at IS NOT NULL AND genre IS NOT NULL");
    final args = <Object?>[accountKey];
    if (type != null) {
      where.write(' AND type = ?');
      args.add(type.name);
    } else {
      where.write(
          " AND type IN ('${ContentType.movie.name}', '${ContentType.series.name}')");
    }
    final rows = await db.query(
      'catalog_items',
      columns: ['genre', 'type', 'category_id'],
      where: where.toString(),
      whereArgs: args,
    );
    // Aggregate case-insensitively but keep the first-seen display casing.
    // Titles in a locked category are skipped entirely so a locked shelf's
    // content doesn't leak into the genre facets (individual item locks are
    // handled at display/open time, not here).
    final counts = <String, int>{};
    final display = <String, String>{};
    for (final r in rows) {
      final catKey = '${r['type']}:${r['category_id']}';
      if (lockedCategoryKeys.contains(catKey)) continue;
      // Kids allowlist: only categories on the list contribute genres, so a
      // blocked shelf's genre (and its count) never appears on the landing.
      if (allowedCategoryKeys != null && !allowedCategoryKeys.contains(catKey)) {
        continue;
      }
      for (final token in splitGenres(r['genre'] as String?)) {
        final key = token.toLowerCase();
        counts[key] = (counts[key] ?? 0) + 1;
        display.putIfAbsent(key, () => token);
      }
    }
    final result = [
      for (final e in counts.entries)
        (genre: display[e.key]!, count: e.value),
    ];
    result.sort((a, b) {
      final c = b.count.compareTo(a.count);
      return c != 0 ? c : a.genre.toLowerCase().compareTo(b.genre.toLowerCase());
    });
    return result;
  }

  /// Enriched items tagged with [genre] (exact token match, cutting across
  /// categories), for the genre drill-in grid. A cheap `LIKE` prefilter narrows
  /// the scan, then each candidate's genre is tokenized so "Action" doesn't
  /// match "Reaction". [type] null = movies + series combined.
  Future<List<CatalogRow>> byGenre(
    String accountKey,
    String genre, {
    ContentType? type,
    int limit = 1000,
  }) async {
    final db = await _database;
    final where = StringBuffer(
        "account_key = ? AND enriched_at IS NOT NULL AND genre LIKE ?");
    final args = <Object?>[accountKey, '%$genre%'];
    if (type != null) {
      where.write(' AND type = ?');
      args.add(type.name);
    } else {
      where.write(
          " AND type IN ('${ContentType.movie.name}', '${ContentType.series.name}')");
    }
    // A generous safety bound so a pathologically huge genre can't load an
    // unbounded result set into memory (and then client-side sort/filter it).
    // Applied to the LIKE prefilter, so in the rare over-limit case a few
    // beyond the cut are dropped before the exact-token filter — fine at this
    // size; realistically no single genre in a personal catalog hits it.
    final rows = await db.query(
      'catalog_items',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'name COLLATE NOCASE',
      limit: limit,
    );
    final wanted = genre.toLowerCase();
    return rows
        .where((r) => splitGenres(r['genre'] as String?)
            .any((t) => t.toLowerCase() == wanted))
        .map(CatalogRow.fromDbMap)
        .toList();
  }

  Future<List<CatalogRow>> search(
    String accountKey,
    String query, {
    ContentType? type,
    int limit = 200,
    bool matchCredits = false,
  }) async {
    final db = await _database;
    final where = StringBuffer('account_key = ?')
      ..write(_nameOrCreditsClause(matchCredits));
    final args = <Object?>[accountKey, ..._nameOrCreditsArgs(query, matchCredits)];
    if (type != null) {
      where.write(' AND type = ?');
      args.add(type.name);
    }
    final rows = await db.query(
      'catalog_items',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'name COLLATE NOCASE',
      limit: limit,
    );
    return rows.map(CatalogRow.fromDbMap).toList();
  }

  /// The `name LIKE ?` clause, widened to also match cast/director/genre when
  /// [matchCredits] is set (enhanced search on). Kept alongside
  /// [_nameOrCreditsArgs] so the two stay in lockstep.
  static String _nameOrCreditsClause(bool matchCredits) => matchCredits
      ? ' AND (name LIKE ? OR cast_names LIKE ? OR director LIKE ? OR genre LIKE ?)'
      : ' AND name LIKE ?';

  static List<Object?> _nameOrCreditsArgs(String query, bool matchCredits) {
    final like = '%$query%';
    return matchCredits ? [like, like, like, like] : [like];
  }

  /// The most recently added items, newest first, for the Recently Added
  /// view. [type] null means movies + series combined (live channels have no
  /// meaningful "added" date and are excluded). Items the panel never dated
  /// (null added_at) are excluded rather than shown in an arbitrary spot.
  Future<List<CatalogRow>> recentlyAdded(
    String accountKey, {
    ContentType? type,
    int limit = 100,
  }) async {
    final db = await _database;
    final where = StringBuffer('account_key = ? AND added_at IS NOT NULL');
    final args = <Object?>[accountKey];
    if (type != null) {
      where.write(' AND type = ?');
      args.add(type.name);
    } else {
      where.write(
          " AND type IN ('${ContentType.movie.name}', '${ContentType.series.name}')");
    }
    final rows = await db.query(
      'catalog_items',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'added_at DESC',
      limit: limit,
    );
    return rows.map(CatalogRow.fromDbMap).toList();
  }

  /// Same filter as [search] but just the row count - used for per-tab
  /// match badges without pulling back full rows for tabs that aren't
  /// even selected.
  Future<int> searchCount(
    String accountKey,
    String query, {
    ContentType? type,
    bool matchCredits = false,
    Set<String> lockedCategoryKeys = const {},
    Set<String>? allowedCategoryKeys,
  }) async {
    final db = await _database;
    final where = StringBuffer('account_key = ?')
      ..write(_nameOrCreditsClause(matchCredits));
    final args = <Object?>[accountKey, ..._nameOrCreditsArgs(query, matchCredits)];
    if (type != null) {
      where.write(' AND type = ?');
      args.add(type.name);
    }
    // Exclude titles in a locked category so the tab-count badges match the
    // category-lock-filtered result list. Keys are 'type:categoryId'; compared
    // against each row's own type+category so it works with or without a type
    // filter. Item-level locks are NOT excluded — those rows still show.
    if (lockedCategoryKeys.isNotEmpty) {
      final placeholders =
          List.filled(lockedCategoryKeys.length, '?').join(', ');
      where.write(
          " AND (type || ':' || COALESCE(category_id, '')) NOT IN ($placeholders)");
      args.addAll(lockedCategoryKeys);
    }
    // Kids allowlist (non-null only in a kids profile): count ONLY titles in an
    // allowed category, so the badge matches the allowlist-filtered list. An
    // empty allowlist means nothing is visible -> count 0.
    if (allowedCategoryKeys != null) {
      if (allowedCategoryKeys.isEmpty) {
        where.write(' AND 0');
      } else {
        final placeholders =
            List.filled(allowedCategoryKeys.length, '?').join(', ');
        where.write(
            " AND (type || ':' || COALESCE(category_id, '')) IN ($placeholders)");
        args.addAll(allowedCategoryKeys);
      }
    }
    final result = await db.rawQuery(
      'SELECT COUNT(*) as c FROM catalog_items WHERE $where',
      args,
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// A map of every indexed item's category, keyed 'type:id' (e.g.
  /// 'live:5' -> '12'). Lets features that only hold a denormalized
  /// snapshot (Favorites/Search/Watch History) resolve an item's category
  /// authoritatively - so category-level PIN locks apply even to favorites
  /// saved before their category was known. Empty until the catalog syncs.
  Future<Map<String, String>> categoryIndexFor(String accountKey) async {
    final db = await _database;
    final rows = await db.query(
      'catalog_items',
      columns: ['type', 'id', 'category_id'],
      where: 'account_key = ? AND category_id IS NOT NULL',
      whereArgs: [accountKey],
    );
    final index = <String, String>{};
    for (final row in rows) {
      final categoryId = row['category_id'] as String?;
      if (categoryId == null || categoryId.isEmpty) continue;
      index['${row['type']}:${row['id']}'] = categoryId;
    }
    return index;
  }

  /// Every indexed item of [type] for an account, name-ordered. Xtream browses
  /// live from its API, but M3U has no such API — the parsed playlist *is* the
  /// catalog, so the M3U source reads categories/streams straight from here.
  Future<List<CatalogRow>> itemsForType(
      String accountKey, ContentType type) async {
    final db = await _database;
    final rows = await db.query(
      'catalog_items',
      where: 'account_key = ? AND type = ?',
      whereArgs: [accountKey, type.name],
      orderBy: 'name COLLATE NOCASE',
    );
    return rows.map(CatalogRow.fromDbMap).toList();
  }

  /// The items of one category only — lets the M3U source answer a category
  /// tap with a WHERE clause instead of loading the whole type into memory.
  Future<List<CatalogRow>> itemsInCategory(
      String accountKey, ContentType type, String categoryId,
      {int? limit}) async {
    final db = await _database;
    final rows = await db.query(
      'catalog_items',
      where: 'account_key = ? AND type = ? AND category_id = ?',
      whereArgs: [accountKey, type.name, categoryId],
      orderBy: 'name COLLATE NOCASE',
      limit: limit,
    );
    return rows.map(CatalogRow.fromDbMap).toList();
  }

  /// The distinct category ids present for [type], sorted case-insensitively.
  /// (For M3U these double as the display names — the group-title strings.)
  Future<List<String>> categoryIdsForType(
      String accountKey, ContentType type) async {
    final db = await _database;
    final rows = await db.rawQuery(
      'SELECT DISTINCT category_id FROM catalog_items '
      'WHERE account_key = ? AND type = ? '
      'ORDER BY category_id COLLATE NOCASE',
      [accountKey, type.name],
    );
    return [for (final r in rows) r['category_id'] as String];
  }

  /// A single catalog item by (account, type, id), or null. Used by the M3U
  /// source to resolve a channel's `tvg-id` (kept in `extra`) for EPG lookups.
  Future<CatalogRow?> itemById(
      String accountKey, ContentType type, String id) async {
    final db = await _database;
    final rows = await db.query(
      'catalog_items',
      where: 'account_key = ? AND type = ? AND id = ?',
      whereArgs: [accountKey, type.name, id],
      limit: 1,
    );
    return rows.isEmpty ? null : CatalogRow.fromDbMap(rows.first);
  }

  /// Replaces all XMLTV programmes for an account with [programmes] (one
  /// transaction, so a channel guide never appears half-updated).
  Future<void> replaceXmltv(
      String accountKey, List<XmltvProgramme> programmes) async {
    final db = await _database;
    await db.transaction((txn) async {
      await txn.delete('epg_programmes',
          where: 'account_key = ?', whereArgs: [accountKey]);
      final batch = txn.batch();
      for (final p in programmes) {
        batch.insert('epg_programmes', {
          'account_key': accountKey,
          'channel_id': p.channelId,
          'start_ms': p.start.millisecondsSinceEpoch,
          'stop_ms': p.stop.millisecondsSinceEpoch,
          'title': p.title,
          'description': p.description,
        });
      }
      await batch.commit(noResult: true);
    });
  }

  /// Programmes for one channel overlapping the window `[fromMs, toMs)`, ordered
  /// by start. `stop_ms > fromMs` keeps the currently-airing programme; an
  /// optional [limit] supports the now/next strip (a few upcoming programmes).
  Future<List<Map<String, Object?>>> epgProgrammes(
    String accountKey,
    String channelId, {
    required int fromMs,
    required int toMs,
    int? limit,
  }) async {
    final db = await _database;
    return db.query(
      'epg_programmes',
      where: 'account_key = ? AND channel_id = ? AND stop_ms > ? AND start_ms < ?',
      whereArgs: [accountKey, channelId, fromMs, toMs],
      orderBy: 'start_ms',
      limit: limit,
    );
  }

  Future<int> countFor(String accountKey, {ContentType? type}) async {
    final db = await _database;
    final where = StringBuffer('account_key = ?');
    final args = <Object?>[accountKey];
    if (type != null) {
      where.write(' AND type = ?');
      args.add(type.name);
    }
    final result = await db.rawQuery(
      'SELECT COUNT(*) as c FROM catalog_items WHERE $where',
      args,
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// When [type] last finished a successful sync, or null if it never has.
  Future<DateTime?> typeSyncedAt(String accountKey, ContentType type) async {
    final db = await _database;
    final rows = await db.query(
      'sync_meta',
      where: 'account_key = ? AND type = ?',
      whereArgs: [accountKey, type.name],
    );
    if (rows.isEmpty) return null;
    final millis = rows.first['last_synced_at'] as int?;
    return millis != null ? DateTime.fromMillisecondsSinceEpoch(millis) : null;
  }

  Future<void> setTypeSyncedAt(
    String accountKey,
    ContentType type,
    DateTime time,
  ) async {
    final db = await _database;
    await db.insert(
      'sync_meta',
      {
        'account_key': accountKey,
        'type': type.name,
        'last_synced_at': time.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Wipes a removed account's cached catalog/sync state so it doesn't
  /// linger on disk or collide if the same server+username is added again.
  Future<void> deleteForAccount(String accountKey) async {
    final db = await _database;
    await db.delete('catalog_items',
        where: 'account_key = ?', whereArgs: [accountKey]);
    await db.delete('sync_meta', where: 'account_key = ?', whereArgs: [accountKey]);
    await db.delete('detail_cache', where: 'account_key = ?', whereArgs: [accountKey]);
    await db.delete('epg_cache', where: 'account_key = ?', whereArgs: [accountKey]);
    await db.delete('epg_programmes',
        where: 'account_key = ?', whereArgs: [accountKey]);
  }

  /// Re-keys every cached row from [oldKey] to [newKey] across all tables.
  /// Used by the one-time profiles migration, which changes an account's key
  /// (it gained a profile-id prefix) without wanting to drop and re-index its
  /// catalog. No-op if the database file doesn't exist yet.
  Future<void> reassignAccountKey(String oldKey, String newKey) async {
    if (oldKey == newKey) return;
    final db = await _database;
    for (final table in const [
      'catalog_items',
      'sync_meta',
      'detail_cache',
      'epg_cache',
      'epg_programmes',
    ]) {
      await db.update(
        table,
        {'account_key': newKey},
        where: 'account_key = ?',
        whereArgs: [oldKey],
      );
    }
  }
}
