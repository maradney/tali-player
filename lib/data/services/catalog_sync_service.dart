import 'package:flutter/foundation.dart' hide Category;

import '../api/xtream_api_service.dart';
import '../db/catalog_database.dart';
import '../models/account.dart';
import '../models/catalog_row.dart';
import '../models/category.dart';
import '../models/search_result.dart';
import '../sources/m3u_media_source.dart';

/// How many of a single content type's categories are fetched at once.
/// Deliberately 1: all three content types sync concurrently, so at
/// concurrency 1 the combined in-flight request count stays around 3 (one
/// per type) instead of ~6. That headroom is what keeps the background
/// index from tripping the panel's 429 "too many requests" limit while the
/// user is also browsing (each browse action fires its own requests).
const _categoryConcurrency = 1;

/// Pause between category fetches within a content type. Longer than
/// correctness requires - it intentionally paces the background index down
/// so it sips at the panel's request budget rather than gulping, again to
/// leave room for the user's own navigation.
const _interChunkDelay = Duration(milliseconds: 800);

/// Keeps the local search index (SQLite) up to date. Meant to run in the
/// background: login kicks this off without awaiting it, so indexing
/// never blocks the UI - by the time the person opens Search, some or
/// all of the catalog is usually already there.
///
/// A `ChangeNotifier` so the UI (a small progress toast, and Search's
/// per-tab enabled state) can reflect what's happening without polling -
/// see [isSyncing]/[stage]/[progress]/[isTypeIndexed].
class CatalogSyncService extends ChangeNotifier {
  CatalogSyncService._();
  static final CatalogSyncService instance = CatalogSyncService._();

  // Guards against two syncs running at once for the same account (e.g.
  // login's background sync and a manual refresh tap overlapping).
  final Set<String> _syncing = {};

  // Which content types have a completed sync on disk, per account. Seeded
  // lazily from the database (see [hydrateIndexedTypes]) so a restart
  // doesn't forget that yesterday's index is still there and usable.
  final Map<String, Set<ContentType>> _indexedTypes = {};
  final Set<String> _hydrated = {};

  bool _isSyncing = false;
  int _completedCategories = 0;
  int _totalCategories = 0;

  // Live/Movies/Series sync concurrently rather than one after another -
  // each stays in here for as long as it's actively fetching, so [stage]
  // can show all of them at once and shrink as each finishes.
  final Set<ContentType> _activeStages = {};

  bool get isSyncing => _isSyncing;

  /// The content types currently being fetched, in [ContentType] order. The
  /// UI maps these to localized labels (a service has no BuildContext, so no
  /// display strings live here).
  List<ContentType> get activeStages =>
      ContentType.values.where(_activeStages.contains).toList();

  /// 0.0-1.0, or null while the category counts aren't known yet (so the
  /// UI can show an indeterminate spinner instead of a stuck-at-0 bar).
  double? get progress =>
      _totalCategories == 0 ? null : _completedCategories / _totalCategories;

  bool isSyncingAccount(Account account) =>
      _syncing.contains(CatalogRow.accountKeyFor(account));

  bool isTypeIndexed(Account account, ContentType type) =>
      _indexedTypes[CatalogRow.accountKeyFor(account)]?.contains(type) ??
      false;

  bool isAllIndexed(Account account) =>
      ContentType.values.every((t) => isTypeIndexed(account, t));

  /// Loads which types already have a completed sync sitting on disk from
  /// a previous run. Call once when a screen that needs this state
  /// (Search) first appears - without this, tabs would look "not indexed
  /// yet" every app restart even though the data is already there.
  Future<void> hydrateIndexedTypes(Account account) async {
    final key = CatalogRow.accountKeyFor(account);
    if (_hydrated.contains(key)) return;
    _hydrated.add(key);

    final indexed = <ContentType>{};
    for (final type in ContentType.values) {
      final syncedAt = await CatalogDatabase.instance.typeSyncedAt(key, type);
      if (syncedAt != null) indexed.add(type);
    }
    _indexedTypes[key] = indexed;
    notifyListeners();
  }

  /// Syncs only if there's no record of a sync, or the last one is older
  /// than [minInterval]. This is what avoids re-fetching the whole
  /// catalog every single time the app opens.
  Future<void> syncIfNeeded(
    Account account,
    XtreamApiService api, {
    Duration minInterval = const Duration(minutes: 15),
  }) async {
    await hydrateIndexedTypes(account);
    final key = CatalogRow.accountKeyFor(account);
    var needsSync = false;
    for (final type in ContentType.values) {
      final last = await CatalogDatabase.instance.typeSyncedAt(key, type);
      if (last == null || DateTime.now().difference(last) >= minInterval) {
        needsSync = true;
        break;
      }
    }
    if (!needsSync) return;
    await fullSync(account, api);
  }

  /// Forces a full resync regardless of when the last one ran - used by
  /// the manual refresh button in Search.
  Future<void> fullSync(Account account, XtreamApiService api) async {
    final key = CatalogRow.accountKeyFor(account);
    if (_syncing.contains(key)) return;
    _syncing.add(key);

    _isSyncing = true;
    _completedCategories = 0;
    _totalCategories = 0;
    _activeStages.clear();
    notifyListeners();

    try {
      // M3U has no per-category API: fetch + parse the playlist into the catalog
      // in one shot, then mark every type indexed. [api] is unused for M3U.
      if (account.isM3u) {
        await M3uMediaSource(account).refresh();
        _indexedTypes.putIfAbsent(key, () => {}).addAll(ContentType.values);
        return;
      }
      // All three run at once - each is mostly waiting on the network, not
      // the CPU, so there's no reason to make Series wait for Live and
      // Movies to fully finish first. Per-type concurrency is kept at 1
      // (see [_categoryConcurrency]) precisely because they run together:
      // that caps the combined request rate low enough to coexist with the
      // user's browsing without provoking 429s.
      await Future.wait([
        _syncType(
          account,
          api,
          type: ContentType.live,
          getCategories: (a) => api.getLiveCategories(a,
              maxRetries: XtreamApiService.backgroundMaxRetries),
          getItemsForCategory: (a, catId) async {
            final channels = await api.getLiveStreams(a, catId,
                maxRetries: XtreamApiService.backgroundMaxRetries);
            return [
              for (final c in channels)
                CatalogRow(
                  accountKey: key,
                  type: ContentType.live,
                  id: c.streamId,
                  name: c.name,
                  categoryId: catId,
                  imageUrl: c.logoUrl,
                ),
            ];
          },
        ),
        _syncType(
          account,
          api,
          type: ContentType.movie,
          getCategories: (a) => api.getVodCategories(a,
              maxRetries: XtreamApiService.backgroundMaxRetries),
          getItemsForCategory: (a, catId) async {
            final movies = await api.getVodStreams(a, catId,
                maxRetries: XtreamApiService.backgroundMaxRetries);
            return [
              for (final m in movies)
                CatalogRow(
                  accountKey: key,
                  type: ContentType.movie,
                  id: m.streamId,
                  name: m.name,
                  categoryId: catId,
                  imageUrl: m.posterUrl,
                  addedAt: m.addedAt,
                  extra: {
                    'containerExtension': m.containerExtension,
                    if (m.rating != null) 'rating': m.rating,
                  },
                ),
            ];
          },
        ),
        _syncType(
          account,
          api,
          type: ContentType.series,
          getCategories: (a) => api.getSeriesCategories(a,
              maxRetries: XtreamApiService.backgroundMaxRetries),
          getItemsForCategory: (a, catId) async {
            final series = await api.getSeries(a, catId,
                maxRetries: XtreamApiService.backgroundMaxRetries);
            return [
              for (final s in series)
                CatalogRow(
                  accountKey: key,
                  type: ContentType.series,
                  id: s.seriesId,
                  name: s.name,
                  categoryId: catId,
                  imageUrl: s.coverUrl,
                  addedAt: s.addedAt,
                  extra: {
                    if (s.rating != null) 'rating': s.rating,
                  },
                ),
            ];
          },
        ),
      ]);
    } catch (_) {
      // fullSync is normally fired-and-forgotten from login/search - never
      // let a failure here surface as an unhandled exception.
    } finally {
      _syncing.remove(key);
      _isSyncing = false;
      _activeStages.clear();
      notifyListeners();
    }
  }

  /// Fetches every category for one content type with limited concurrency
  /// ([_categoryConcurrency], one at a time), spaced out by
  /// [_interChunkDelay], rather than firing "everything at once" (which
  /// reliably trips 429 rate limiting on smaller panels). Kept deliberately
  /// gentle since [fullSync] runs all three content types concurrently too -
  /// this keeps the combined request rate low enough to share the panel's
  /// budget with the user's own browsing. A failing category is skipped
  /// rather than aborting the type; if even the category list call fails,
  /// the type is left as whatever was indexed on a previous sync (never
  /// wiped for a transient failure).
  ///
  /// Persists straight to disk and marks the type as indexed as soon as
  /// it finishes, rather than waiting for all three types - so e.g. Live
  /// becomes searchable while Movies/Series are still syncing.
  Future<void> _syncType(
    Account account,
    XtreamApiService api, {
    required ContentType type,
    required Future<List<Category>> Function(Account) getCategories,
    required Future<List<CatalogRow>> Function(Account, String categoryId)
        getItemsForCategory,
    int concurrency = _categoryConcurrency,
  }) async {
    _activeStages.add(type);
    notifyListeners();

    try {
      List<Category> categories;
      try {
        categories = await getCategories(account);
      } catch (_) {
        return;
      }

      _totalCategories += categories.length;
      notifyListeners();

      final results = <CatalogRow>[];

      for (var i = 0; i < categories.length; i += concurrency) {
        final chunk = categories.skip(i).take(concurrency);
        final chunkResults = await Future.wait(
          chunk.map((cat) async {
            try {
              return await getItemsForCategory(account, cat.categoryId);
            } catch (_) {
              return <CatalogRow>[];
            }
          }),
        );
        for (final list in chunkResults) {
          results.addAll(list);
        }
        _completedCategories += chunkResults.length;
        notifyListeners();

        // Pause between chunks so we stay under panels' rate limits instead
        // of hammering them with back-to-back bursts.
        if (i + concurrency < categories.length) {
          await Future.delayed(_interChunkDelay);
        }
      }

      final key = CatalogRow.accountKeyFor(account);
      await CatalogDatabase.instance.replaceTypeItems(key, type, results);
      await CatalogDatabase.instance.setTypeSyncedAt(key, type, DateTime.now());
      _indexedTypes.putIfAbsent(key, () => {}).add(type);
    } finally {
      _activeStages.remove(type);
      notifyListeners();
    }
  }
}
