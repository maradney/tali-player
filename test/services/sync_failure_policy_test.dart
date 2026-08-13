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
  _ScriptedAdapter({this.failCategoriesFor, this.failItemsFor});

  /// Actions whose *category list* always fails, e.g. 'get_live_categories'.
  final Set<String>? failCategoriesFor;

  /// Actions whose *item* fetch always fails, e.g. 'get_live_streams'.
  final Set<String>? failItemsFor;

  final List<String> requested = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final action = options.uri.queryParameters['action'] ?? '';
    requested.add(action);
    if ((failCategoriesFor?.contains(action) ?? false) ||
        (failItemsFor?.contains(action) ?? false)) {
      return ResponseBody.fromString('nope', 500);
    }
    return ResponseBody.fromString(
      jsonEncode(_payloadFor(action)),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  Object _payloadFor(String action) {
    if (action.contains('categories')) {
      return [
        {'category_id': '1', 'category_name': 'A'},
      ];
    }
    if (action == 'get_live_streams') {
      return [
        {'stream_id': '10', 'name': 'Chan', 'category_id': '1'},
      ];
    }
    if (action == 'get_vod_streams') {
      return [
        {
          'stream_id': '20',
          'name': 'Movie',
          'category_id': '1',
          'container_extension': 'mp4'
        },
      ];
    }
    if (action == 'get_series') {
      return [
        {'series_id': '30', 'name': 'Series', 'category_id': '1'},
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

  test('a partial fetch does not overwrite a complete catalog', () async {
    // replaceTypeItems deletes before inserting, so writing a partial result
    // would destroy rows the panel simply failed to re-serve this time.
    final account = accountNamed('partial-keeps-data');
    final key = CatalogRow.accountKeyFor(account);

    await sync.fullSync(account, apiWith(_ScriptedAdapter()));
    final good = await db.countFor(key, type: ContentType.live);
    final syncedAt = await db.typeSyncedAt(key, ContentType.live);
    expect(good, greaterThan(0), reason: 'setup: first sync should populate');

    // Now the items fail while the category list still succeeds.
    await sync.fullSync(
      account,
      apiWith(_ScriptedAdapter(failItemsFor: {'get_live_streams'})),
    );

    expect(await db.countFor(key, type: ContentType.live), good,
        reason: 'existing rows must survive a failed refresh');
    expect(await db.typeSyncedAt(key, ContentType.live), syncedAt,
        reason: 'a failed refresh must not look like a fresh one');
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
