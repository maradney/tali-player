import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/api/xtream_api_service.dart';
import 'package:iptv_player/data/db/catalog_database.dart';
import 'package:iptv_player/data/models/catalog_row.dart';
import 'package:iptv_player/data/models/search_result.dart';
import 'package:iptv_player/data/services/catalog_sync_service.dart';
import 'package:iptv_player/data/services/diagnostics_log.dart';

import '../support/test_support.dart';

/// Live and Movies sat at "0 items indexed / Updated never" across every
/// launch while Series was fine, and search stayed disabled for them and for
/// All. Two defects, both about what a failed fetch is allowed to do:
///
///   - a failed category list abandoned the whole content type silently, and
///   - a partly- or wholly-failed fetch was still written and marked synced,
///     and since the write deletes before it inserts, that destroyed the rows
///     the panel had merely failed to re-serve.
///
/// The rule now is that only a fully successful fetch may replace what is
/// stored, and anything less leaves both the data and the "never synced"
/// state alone so the next attempt retries.
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter({
    this.failCategoriesFor,
    this.failItemsFor,
    this.categoryIds = const ['1', '2', '3'],
    this.failItemsForCategories = const {},
  });

  /// Actions whose *category list* always fails, e.g. 'get_live_categories'.
  final Set<String>? failCategoriesFor;

  /// Actions whose *item* fetch always fails, e.g. 'get_live_streams'.
  final Set<String>? failItemsFor;

  /// Categories the panel serves.
  final List<String> categoryIds;

  /// Categories whose *item* fetch fails while the others succeed - the
  /// partial-failure shape the real panel produced (6 of 44).
  final Set<String> failItemsForCategories;

  final List<String> requested = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final action = options.uri.queryParameters['action'] ?? '';
    final categoryId = options.uri.queryParameters['category_id'];
    requested.add(action);
    if ((failCategoriesFor?.contains(action) ?? false) ||
        (failItemsFor?.contains(action) ?? false) ||
        (categoryId != null && failItemsForCategories.contains(categoryId))) {
      return ResponseBody.fromString('nope', 500);
    }
    return ResponseBody.fromString(
      jsonEncode(_payloadFor(action, categoryId)),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  /// One item per category, with an id derived from the category, so a test
  /// can tell *which* categories' rows are in the database.
  Object _payloadFor(String action, String? categoryId) {
    if (action.contains('categories')) {
      return [
        for (final id in categoryIds)
          {'category_id': id, 'category_name': 'Cat $id'},
      ];
    }
    final cat = categoryId ?? '1';
    if (action == 'get_live_streams') {
      return [
        {'stream_id': '10$cat', 'name': 'Chan $cat', 'category_id': cat},
      ];
    }
    if (action == 'get_vod_streams') {
      return [
        {
          'stream_id': '20$cat',
          'name': 'Movie $cat',
          'category_id': cat,
          'container_extension': 'mp4'
        },
      ];
    }
    if (action == 'get_series') {
      return [
        {'series_id': '30$cat', 'name': 'Series $cat', 'category_id': cat},
      ];
    }
    return const [];
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  final sync = CatalogSyncService.instance;
  final db = CatalogDatabase.instance;

  setUpAll(() async {
    await initDbEnvironment();
  });

  XtreamApiService apiWith(_ScriptedAdapter adapter) =>
      XtreamApiService(dio: Dio()..httpClientAdapter = adapter);

  test('a type whose category list fails is left unsynced, not marked done',
      () async {
    // Unsynced is what makes the next launch try again. Marking it would
    // strand the section at "0 items / Updated never" forever, which is the
    // reported bug.
    final account = accountNamed('cat-list-fails');
    final key = CatalogRow.accountKeyFor(account);
    final adapter =
        _ScriptedAdapter(failCategoriesFor: {'get_live_categories'});

    await sync.fullSync(account, apiWith(adapter));

    expect(await db.typeSyncedAt(key, ContentType.live), isNull,
        reason: 'live must stay retryable');
    expect(sync.isTypeIndexed(account, ContentType.live), isFalse);
    // The healthy types are unaffected - one failure must not sink the rest.
    expect(await db.typeSyncedAt(key, ContentType.movie), isNotNull);
    expect(await db.typeSyncedAt(key, ContentType.series), isNotNull);
  });

  test('the category list is retried rather than abandoned on first failure',
      () async {
    // Asserted through the diagnostics log rather than the request count: the
    // API layer already retries internally, so a bare count is greater than
    // one either way and would pass against the old give-up-immediately code.
    final account = accountNamed('cat-list-retries');
    DiagnosticsLog.instance.clear();
    final adapter =
        _ScriptedAdapter(failCategoriesFor: {'get_live_categories'});

    await sync.fullSync(account, apiWith(adapter));

    final messages = DiagnosticsLog.instance.entries.map((e) => e.message);
    expect(messages.where((m) => m.contains('retrying in')), isNotEmpty,
        reason: 'the category list should be retried across the rate limit');
    expect(messages.where((m) => m.contains('keeping the previous index')),
        isNotEmpty,
        reason: 'and the give-up should be recorded, not silent');
  });

  test('a partial fetch on a fresh install keeps what did arrive', () async {
    // The defect this file now guards. Two of three categories succeed; the
    // previous policy wrote nothing at all, so a brand-new install ended up
    // with an empty index and search permanently disabled. On the real panel
    // it discarded 38 of 44 categories.
    final account = accountNamed('partial-fresh');
    final key = CatalogRow.accountKeyFor(account);

    await sync.fullSync(
      account,
      apiWith(_ScriptedAdapter(failItemsForCategories: {'3'})),
    );

    expect(await db.countFor(key, type: ContentType.live), 2,
        reason: 'the categories that succeeded must be stored');
    expect(sync.isTypeIndexed(account, ContentType.live), isTrue,
        reason: 'a usable index must not be gated on being a complete one');
    expect(await db.typeSyncedAt(key, ContentType.live), isNotNull);
  });

  test("a partial refresh leaves the failed categories' rows alone", () async {
    // Why the old policy existed at all: replaceTypeItems deletes before it
    // inserts, so a type-wide write of a partial result would destroy rows the
    // panel merely failed to re-serve. Scoping the write to the categories
    // actually fetched keeps both properties at once.
    final account = accountNamed('partial-refresh');
    final key = CatalogRow.accountKeyFor(account);

    await sync.fullSync(account, apiWith(_ScriptedAdapter()));
    expect(await db.countFor(key, type: ContentType.live), 3,
        reason: 'setup: a clean sync should store all three');

    // Now category 3's items fail. Its row must survive; 1 and 2 refresh.
    await sync.fullSync(
      account,
      apiWith(_ScriptedAdapter(failItemsForCategories: {'3'})),
    );

    expect(await db.countFor(key, type: ContentType.live), 3,
        reason: "category 3's row was deleted by a sync that never fetched it");
  });

  test('coverage accumulates when a different subset fails each run', () async {
    // The property that makes a per-category write worth having: two runs that
    // each fail half the catalog still end up with all of it, because neither
    // run deletes what the other fetched. Under the type-wide policy both runs
    // wrote nothing and the total stayed zero forever.
    final account = accountNamed('accumulates');
    final key = CatalogRow.accountKeyFor(account);
    const cats = ['1', '2', '3', '4'];

    await sync.fullSync(
      account,
      apiWith(_ScriptedAdapter(
        categoryIds: cats,
        failItemsForCategories: {'3', '4'},
      )),
    );
    expect(await db.countFor(key, type: ContentType.live), 2);

    // The complementary half fails this time.
    await sync.fullSync(
      account,
      apiWith(_ScriptedAdapter(
        categoryIds: cats,
        failItemsForCategories: {'1', '2'},
      )),
    );

    expect(await db.countFor(key, type: ContentType.live), 4,
        reason: 'the two runs together should cover every category');
  });

  test('a fetch where every category fails writes nothing', () async {
    // Nothing to write means nothing is gained by claiming a sync, and
    // staying unsynced is the mechanism that schedules the retry.
    final account = accountNamed('all-categories-fail');
    final key = CatalogRow.accountKeyFor(account);

    await sync.fullSync(
      account,
      apiWith(_ScriptedAdapter(failItemsFor: {'get_live_streams'})),
    );

    expect(await db.countFor(key, type: ContentType.live), 0);
    expect(await db.typeSyncedAt(key, ContentType.live), isNull,
        reason: 'must stay retryable');
  });

  test('a fully successful fetch does replace what is stored', () async {
    // The guard must not be so cautious that a real sync stops landing.
    final account = accountNamed('success-writes');
    final key = CatalogRow.accountKeyFor(account);

    await sync.fullSync(account, apiWith(_ScriptedAdapter()));

    for (final type in ContentType.values) {
      expect(await db.countFor(key, type: type), greaterThan(0));
      expect(await db.typeSyncedAt(key, type), isNotNull);
      expect(sync.isTypeIndexed(account, type), isTrue);
    }
  });

  test('every type is still attempted when one is failing', () async {
    final account = accountNamed('others-proceed');
    final adapter = _ScriptedAdapter(failItemsFor: {'get_vod_streams'});

    await sync.fullSync(account, apiWith(adapter));
    final key = CatalogRow.accountKeyFor(account);

    expect(await db.typeSyncedAt(key, ContentType.movie), isNull);
    expect(await db.typeSyncedAt(key, ContentType.live), isNotNull);
    expect(await db.typeSyncedAt(key, ContentType.series), isNotNull);
  });
}
