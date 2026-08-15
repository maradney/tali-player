import 'package:flutter/foundation.dart' hide Category;

import '../api/xtream_api_service.dart';
import '../db/catalog_database.dart';
import '../models/account.dart';
import '../models/catalog_row.dart';
import '../models/category.dart';
import '../models/search_result.dart';
import '../sources/m3u_media_source.dart';
import 'diagnostics_log.dart';

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

/// Staggers the three content types' opening request. They sync concurrently,
/// so without this all three ask for their category list in the same instant -
/// the burstiest moment of the whole sync, right at launch, when the user's
/// own screens are also loading. A panel that rate-limits refuses whichever
/// ones it likes least, which is how Live and Movies ended up permanently
/// unindexed while Series was fine.
const _typeStartStagger = Duration(milliseconds: 700);

/// Extra attempts at a type's category list, on top of the API's own retries.
/// The list is a single request that the entire type depends on: lose it and
/// there is nothing to iterate, so it is worth more patience than the
/// per-category fetches get.
const _categoryListAttempts = 3;

/// Backoff between those attempts. Deliberately long - the failure being
/// recovered from is usually a rate limit, which needs time rather than
/// persistence.
const _categoryListBackoff = [Duration(seconds: 3), Duration(seconds: 8)];

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

  /// Hydration currently in flight, so concurrent callers share one pass
  /// rather than the second one short-circuiting on a half-done first.
  final Map<String, Future<void>> _hydrating = {};

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
  ///
  /// Two callers overlap on startup - HomeShell via [syncIfNeeded], and Search
  /// from its own initState - so they share one in-flight pass rather than the
  /// second one short-circuiting on a half-done first.
  ///
  /// The change that matters is *when* the key is marked done. It used to be
  /// claimed before awaiting the database, so a read that threw part-way left
  /// the account permanently marked-but-empty: every Search tab would report
  /// "still indexing" for the rest of the session, with nothing able to retry,
  /// while the counters underneath - read from the database rather than from
  /// this set - reported a catalog that was plainly there. The key is now set
  /// only on success, and the in-flight entry cleared either way.
  Future<void> hydrateIndexedTypes(Account account) {
    final key = CatalogRow.accountKeyFor(account);
    if (_hydrated.contains(key)) return Future<void>.value();
    return _hydrating[key] ??= _hydrate(key);
  }

  Future<void> _hydrate(String key) async {
    try {
      final indexed = <ContentType>{};
      for (final type in ContentType.values) {
        final syncedAt = await CatalogDatabase.instance.typeSyncedAt(key, type);
        if (syncedAt != null) indexed.add(type);
      }
      _indexedTypes[key] = indexed;
      _hydrated.add(key);
      notifyListeners();
    } finally {
      _hydrating.remove(key);
    }
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
          // Live goes first with no delay; the other two are staggered so the
          // three category-list requests do not land together.
          startDelay: Duration.zero,
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
          startDelay: _typeStartStagger,
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
          startDelay: _typeStartStagger * 2,
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
  /// The category list with its own retries, or null if every attempt failed.
  ///
  /// The API already retries internally, but those retries all happen inside
  /// the same burst; a rate limit needs waiting out, not retrying harder. This
  /// adds a few widely-spaced attempts on top, which is affordable because it
  /// is one request per type and the whole type is useless without it.
  Future<List<Category>?> _fetchCategoriesWithRetry(
    Account account, {
    required ContentType type,
    required Future<List<Category>> Function(Account) getCategories,
  }) async {
    for (var attempt = 0; attempt < _categoryListAttempts; attempt++) {
      try {
        return await getCategories(account);
      } catch (_) {
        if (attempt < _categoryListBackoff.length) {
          DiagnosticsLog.instance.add(
            'Sync: ${type.name} category list failed, retrying in '
            '${_categoryListBackoff[attempt].inSeconds}s',
          );
          await Future.delayed(_categoryListBackoff[attempt]);
        }
      }
    }
    return null;
  }

  Future<void> _syncType(
    Account account,
    XtreamApiService api, {
    required ContentType type,
    required Future<List<Category>> Function(Account) getCategories,
    required Future<List<CatalogRow>> Function(Account, String categoryId)
        getItemsForCategory,
    int concurrency = _categoryConcurrency,
    Duration startDelay = Duration.zero,
  }) async {
    if (startDelay > Duration.zero) await Future.delayed(startDelay);
    _activeStages.add(type);
    notifyListeners();

    try {
      final categories = await _fetchCategoriesWithRetry(
        account,
        type: type,
        getCategories: getCategories,
      );
      if (categories == null) {
        // Every attempt failed. Leaving the type unsynced is deliberate: it is
        // what makes the next launch try again. Marking it, or wiping what is
        // already stored, would turn a transient refusal into a permanent
        // empty section - which is exactly how Live and Movies ended up stuck
        // at "0 items indexed / Updated never" across restarts.
        DiagnosticsLog.instance.add(
          'Sync: ${type.name} category list failed after $_categoryListAttempts '
          'attempts — keeping the previous index',
        );
        return;
      }

      _totalCategories += categories.length;
      notifyListeners();

      final results = <CatalogRow>[];
      // Which categories actually came back, so a partial result can be written
      // without touching the rows of the ones that did not.
      final fetched = <String>{};
      var failedCategories = 0;

      for (var i = 0; i < categories.length; i += concurrency) {
        final chunk = categories.skip(i).take(concurrency);
        final chunkResults = await Future.wait(
          chunk.map((cat) async {
            try {
              final rows = await getItemsForCategory(account, cat.categoryId);
              fetched.add(cat.categoryId);
              return rows;
            } catch (_) {
              // Counted, not swallowed: which categories failed decides what
              // may be overwritten below.
              failedCategories++;
              return null;
            }
          }),
        );
        for (final list in chunkResults) {
          if (list != null) results.addAll(list);
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

      if (failedCategories > 0) {
        // A partial result must not delete the rows of categories the panel
        // merely failed to re-serve - but it must not be thrown away either.
        // An earlier version of this returned here, and on a real sync that
        // discarded the 38 categories of 44 that had succeeded. Write the ones
        // that came back and leave the rest alone.
        if (fetched.isEmpty) {
          DiagnosticsLog.instance.add(
            'Sync: ${type.name} failed — all ${categories.length} categories '
            'unavailable, nothing written',
          );
          return;
        }
        await CatalogDatabase.instance
            .replaceCategoryItems(key, type, fetched, results);
        // Marked usable even though incomplete: these are two different
        // questions, and conflating them is what left search disabled while
        // most of the catalog sat in the database. The type is still due a
        // refresh, which the ordinary interval takes care of, and because the
        // write is per-category the coverage accumulates run over run.
        await CatalogDatabase.instance
            .setTypeSyncedAt(key, type, DateTime.now());
        _indexedTypes.putIfAbsent(key, () => {}).add(type);
        DiagnosticsLog.instance.add(
          'Sync: ${type.name} partial — wrote ${fetched.length} of '
          '${categories.length} categories (${results.length} items), '
          '$failedCategories failed and were left as they were',
        );
        return;
      }

      await CatalogDatabase.instance.replaceTypeItems(key, type, results);
      await CatalogDatabase.instance.setTypeSyncedAt(key, type, DateTime.now());
      _indexedTypes.putIfAbsent(key, () => {}).add(type);
    } finally {
      _activeStages.remove(type);
      notifyListeners();
    }
  }
}
