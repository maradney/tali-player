import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/api/xtream_api_service.dart';
import 'package:iptv_player/data/db/catalog_database.dart';
import 'package:iptv_player/data/models/search_result.dart';
import 'package:iptv_player/data/services/catalog_sync_service.dart';

import '../support/test_support.dart';

/// A Dio adapter that answers the catalog endpoints and tracks how many
/// requests are in flight at once, so a test can assert the background sync
/// stays gentle on the panel.
class _ConcurrencyProbeAdapter implements HttpClientAdapter {
  int _inFlight = 0;
  int maxInFlight = 0;

  // Hold each "connection" open briefly so overlapping requests actually
  // overlap in the counter rather than completing instantly and in order.
  static const _hold = Duration(milliseconds: 20);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    _inFlight++;
    if (_inFlight > maxInFlight) maxInFlight = _inFlight;
    try {
      await Future.delayed(_hold);
      final action = options.uri.queryParameters['action'] ?? '';
      return ResponseBody.fromString(
        jsonEncode(_payloadFor(action)),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    } finally {
      _inFlight--;
    }
  }

  Object _payloadFor(String action) {
    if (action.contains('categories')) {
      return [
        {'category_id': '1', 'category_name': 'A'},
        {'category_id': '2', 'category_name': 'B'},
      ];
    }
    if (action == 'get_live_streams') {
      return [
        {'stream_id': '10', 'name': 'Chan', 'category_id': '1'},
      ];
    }
    if (action == 'get_vod_streams') {
      return [
        {'stream_id': '20', 'name': 'Movie', 'category_id': '1', 'container_extension': 'mp4'},
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

  setUpAll(() async {
    await initDbEnvironment();
  });

  test('an account with no synced types is not indexed and not syncing', () {
    final account = accountNamed('sync-fresh');
    expect(sync.isSyncingAccount(account), isFalse);
    expect(sync.isTypeIndexed(account, ContentType.live), isFalse);
    expect(sync.isAllIndexed(account), isFalse);
  });

  test('hydrateIndexedTypes reflects sync metadata already on disk', () async {
    final account = accountNamed('sync-hydrate');
    // Only live + movie have finished a sync; series has not.
    await CatalogDatabase.instance
        .setTypeSyncedAt(account.key, ContentType.live, DateTime.now());
    await CatalogDatabase.instance
        .setTypeSyncedAt(account.key, ContentType.movie, DateTime.now());

    await sync.hydrateIndexedTypes(account);

    expect(sync.isTypeIndexed(account, ContentType.live), isTrue);
    expect(sync.isTypeIndexed(account, ContentType.movie), isTrue);
    expect(sync.isTypeIndexed(account, ContentType.series), isFalse);
    expect(sync.isAllIndexed(account), isFalse);
  });

  test('isAllIndexed is true once every type is synced', () async {
    final account = accountNamed('sync-all');
    for (final type in ContentType.values) {
      await CatalogDatabase.instance
          .setTypeSyncedAt(account.key, type, DateTime.now());
    }
    await sync.hydrateIndexedTypes(account);
    expect(sync.isAllIndexed(account), isTrue);
  });

  test('progress is null until a sync sets category totals', () {
    // No sync running -> total categories 0 -> indeterminate.
    expect(sync.progress, isNull);
  });

  // Kept last: fullSync mutates shared counters on the singleton, so run it
  // after the tests that assert on a pristine idle state.
  test('fullSync keeps combined in-flight requests within the gentle cap',
      () async {
    final account = accountNamed('sync-pacing');
    final probe = _ConcurrencyProbeAdapter();
    final api = XtreamApiService(dio: Dio()..httpClientAdapter = probe);

    await sync.fullSync(account, api);

    // Three content types sync concurrently at one category each, so at most
    // ~3 requests are ever in flight together. If per-type concurrency crept
    // back up to 2, the stream-fetch phase would peak at 6 - this guards the
    // "gentle on the panel" pacing that keeps browsing from hitting 429s.
    expect(probe.maxInFlight, greaterThan(0));
    expect(probe.maxInFlight, lessThanOrEqualTo(3));

    // Sanity: the sync actually completed and indexed every type.
    expect(sync.isAllIndexed(account), isTrue);
  });
}
