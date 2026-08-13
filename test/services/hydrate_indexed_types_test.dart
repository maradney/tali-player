import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/db/catalog_database.dart';
import 'package:iptv_player/data/models/catalog_row.dart';
import 'package:iptv_player/data/models/search_result.dart';
import 'package:iptv_player/data/services/catalog_sync_service.dart';

import '../support/test_support.dart';

/// Invariants for the set that decides whether a Search tab is usable.
///
/// Read the control result before trusting these: the *pre-fix* implementation
/// also passes every test here. Marking the account hydrated before awaiting
/// the database looks like a race, and two callers really do overlap on
/// startup (HomeShell via syncIfNeeded, Search from its own initState) - but
/// the second caller does not need the answer synchronously, and the first
/// still fires notifyListeners when it lands, so the UI catches up either way.
///
/// The defect the fix actually closes is the failure path: if the database
/// read threw part-way, the old code had already claimed the key, so the set
/// stayed empty for the rest of the session with nothing able to retry. That
/// is not reproducible here without a way to make sqflite fail on demand, so
/// these cover the surrounding behaviour instead - that hydration reports the
/// truth, does not over-mark, and keeps accounts independent.
void main() {
  final service = CatalogSyncService.instance;

  setUpAll(() async {
    await initDbEnvironment();
  });

  test('concurrent callers all end up with the indexed state', () async {
    final account = accountNamed('race');
    final key = CatalogRow.accountKeyFor(account);
    for (final type in ContentType.values) {
      await CatalogDatabase.instance.setTypeSyncedAt(key, type, DateTime.now());
    }

    // Both start before either finishes - the shape of the real startup.
    await Future.wait([
      service.hydrateIndexedTypes(account),
      service.hydrateIndexedTypes(account),
    ]);

    for (final type in ContentType.values) {
      expect(service.isTypeIndexed(account, type), isTrue,
          reason: '$type should be known-indexed after hydration');
    }
    expect(service.isAllIndexed(account), isTrue);
  });

  test('a second caller starting later still sees the result', () async {
    final account = accountNamed('late');
    final key = CatalogRow.accountKeyFor(account);
    await CatalogDatabase.instance
        .setTypeSyncedAt(key, ContentType.movie, DateTime.now());

    final first = service.hydrateIndexedTypes(account);
    final second = service.hydrateIndexedTypes(account);
    await Future.wait([first, second]);

    expect(service.isTypeIndexed(account, ContentType.movie), isTrue);
    // Only Movies was ever synced, so the others must stay unindexed - the
    // fix must not paper over the bug by marking everything ready.
    expect(service.isTypeIndexed(account, ContentType.live), isFalse);
    expect(service.isAllIndexed(account), isFalse);
  });

  test('an account with nothing synced reports nothing indexed', () async {
    final account = accountNamed('empty');
    await service.hydrateIndexedTypes(account);
    for (final type in ContentType.values) {
      expect(service.isTypeIndexed(account, type), isFalse);
    }
  });

  test('hydrating twice in sequence is stable', () async {
    // The second call short-circuits on the hydrated flag; it must not clear
    // what the first one established.
    final account = accountNamed('twice');
    final key = CatalogRow.accountKeyFor(account);
    await CatalogDatabase.instance
        .setTypeSyncedAt(key, ContentType.series, DateTime.now());

    await service.hydrateIndexedTypes(account);
    await service.hydrateIndexedTypes(account);

    expect(service.isTypeIndexed(account, ContentType.series), isTrue);
  });

  test('accounts are hydrated independently', () async {
    final a = accountNamed('acct-a');
    final b = accountNamed('acct-b');
    await CatalogDatabase.instance.setTypeSyncedAt(
        CatalogRow.accountKeyFor(a), ContentType.live, DateTime.now());

    await Future.wait([
      service.hydrateIndexedTypes(a),
      service.hydrateIndexedTypes(b),
    ]);

    expect(service.isTypeIndexed(a, ContentType.live), isTrue);
    expect(service.isTypeIndexed(b, ContentType.live), isFalse);
  });
}
