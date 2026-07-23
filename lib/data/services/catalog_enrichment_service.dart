import 'package:flutter/foundation.dart';

import '../api/xtream_api_service.dart';
import '../db/catalog_database.dart';
import '../models/account.dart';
import '../models/catalog_row.dart';
import '../models/search_result.dart';
import 'settings_service.dart';

/// Pause between per-item detail fetches. Deliberately gentler than the
/// category sync's 800ms: enrichment is one request *per title* and there can
/// be thousands, so it sips at the panel's request budget over a long time
/// rather than risking the 429s the whole feature is careful to avoid. Runs
/// strictly one at a time (no concurrency) for the same reason.
const _interItemDelay = Duration(milliseconds: 1200);

/// Optional "enhanced search" crawler: for each movie and series in the local
/// catalog, fetches its detail (get_vod_info / get_series_info) and stores the
/// cast/director/genre so Search and the browse filters can match people and
/// genre, not just titles.
///
/// Off unless [SettingsService.enhancedSearchEnabled] is set. It's incremental
/// and resumable — it only fetches rows not yet enriched (NULL enriched_at), so
/// closing the app mid-crawl or adding content later just continues. Detail is
/// cached on disk anyway (see [XtreamApiService.getVodInfo]), so this doubles as
/// warming that cache. A `ChangeNotifier` so the Settings tile can show live
/// progress without polling.
class CatalogEnrichmentService extends ChangeNotifier {
  CatalogEnrichmentService._();
  static final CatalogEnrichmentService instance =
      CatalogEnrichmentService._();

  // Accounts with a crawl currently running — guards against the login/sync
  // trigger and a manual Rebuild overlapping for the same account.
  final Set<String> _active = {};
  final Map<String, ({int enriched, int total})> _progress = {};

  bool isEnriching(Account account) => _active.contains(account.key);

  /// enriched/total for an account, or null if never counted yet.
  ({int enriched, int total})? progressFor(Account account) =>
      _progress[account.key];

  /// Starts (or continues) the crawl for [account] if the setting is on and it
  /// isn't already running. Fire-and-forget: callers don't await it.
  Future<void> enrichIfEnabled(Account account, XtreamApiService api) async {
    // M3U has no per-item detail endpoint to crawl; enrichment is Xtream-only.
    if (account.isM3u) return;
    if (!SettingsService.instance.enhancedSearchEnabled) return;
    await _run(account, api);
  }

  /// Clears every stored credit for [account] and re-crawls from scratch —
  /// backs the Settings "Rebuild" action. No-op while the setting is off.
  Future<void> rebuild(Account account, XtreamApiService api) async {
    if (account.isM3u) return;
    if (!SettingsService.instance.enhancedSearchEnabled) return;
    await _run(account, api, rebuild: true);
  }

  Future<void> _run(
    Account account,
    XtreamApiService api, {
    bool rebuild = false,
  }) async {
    final key = account.key;
    if (_active.contains(key)) return;
    _active.add(key);
    notifyListeners();

    try {
      if (rebuild) await CatalogDatabase.instance.clearEnrichment(key);
      await _refreshProgress(key);

      // Snapshot the pending set once rather than re-querying in a loop: a row
      // that fails (e.g. a transient error) stays NULL and is simply retried on
      // a later run, instead of being re-selected forever within this one.
      final pending =
          await CatalogDatabase.instance.rowsNeedingEnrichment(key);

      for (final row in pending) {
        // Respect the user turning the setting off mid-crawl.
        if (!SettingsService.instance.enhancedSearchEnabled) break;
        try {
          await _enrichOne(account, api, row);
          final current = _progress[key];
          if (current != null) {
            _progress[key] =
                (enriched: current.enriched + 1, total: current.total);
            notifyListeners();
          }
        } catch (_) {
          // Leave this row NULL so a later run retries it — don't stamp it
          // enriched on failure, or a transient 429 would hide it until a
          // manual rebuild.
        }
        await Future.delayed(_interItemDelay);
      }
    } finally {
      _active.remove(key);
      await _refreshProgress(key);
      notifyListeners();
    }
  }

  Future<void> _enrichOne(
    Account account,
    XtreamApiService api,
    CatalogRow row,
  ) async {
    switch (row.type) {
      case ContentType.movie:
        final info = await api.getVodInfo(account, row.id,
            maxRetries: XtreamApiService.backgroundMaxRetries);
        await CatalogDatabase.instance.saveEnrichment(
          account.key,
          row.type,
          row.id,
          cast: info.cast,
          director: info.director,
          genre: info.genre,
          year: info.year,
          rating: info.rating,
        );
      case ContentType.series:
        final info = await api.getSeriesInfo(account, row.id,
            maxRetries: XtreamApiService.backgroundMaxRetries);
        await CatalogDatabase.instance.saveEnrichment(
          account.key,
          row.type,
          row.id,
          cast: info.cast,
          director: info.director,
          genre: info.genre,
          year: info.year,
          rating: info.rating,
        );
      case ContentType.live:
        break; // never queued — live has no cast/director
    }
  }

  Future<void> _refreshProgress(String accountKey) async {
    _progress[accountKey] =
        await CatalogDatabase.instance.enrichmentProgress(accountKey);
    notifyListeners();
  }
}
