import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../db/catalog_database.dart';
import '../models/account.dart';
import '../models/search_result.dart' show ContentType;
import '../models/watch_history_entry.dart';

/// Singleton, append-only log of what's been opened for playback, so a
/// Watch History screen can show a chronological "what did I watch"
/// timeline. Same ChangeNotifier + per-account shared_preferences pattern
/// as FavoritesService/PlaybackService, but this one is a bounded list
/// rather than a keyed map, since the same item can (and should) reappear
/// each time it's rewatched.
class WatchHistoryService extends ChangeNotifier {
  WatchHistoryService._();
  static final WatchHistoryService instance = WatchHistoryService._();

  static String _prefsKeyFor(String accountKey) => 'watch_history_v1_$accountKey';

  // Enough to feel like real history without the list (and its
  // shared_preferences payload) growing unbounded on a device that's
  // used daily for years.
  static const _maxEntries = 300;

  List<WatchHistoryEntry> _entries = []; // newest first
  String? _loadedAccountKey;

  /// Newest-first log of watched items.
  List<WatchHistoryEntry> get entries => List.unmodifiable(_entries);

  /// The most recently opened live channel, or null if none is on record.
  /// Used by Live TV to offer "resume last channel". Live opens are logged
  /// here (they just aren't shown in the History screen's movie/series grids).
  WatchHistoryEntry? get lastLiveEntry {
    for (final e in _entries) {
      if (e.type == 'live') return e; // _entries is newest-first
    }
    return null;
  }

  Future<void> loadFor(Account account) async {
    if (_loadedAccountKey == account.key) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKeyFor(account.key)) ?? [];
    final entries = <WatchHistoryEntry>[];
    for (final s in raw) {
      try {
        entries.add(WatchHistoryEntry.fromJson(jsonDecode(s)));
      } catch (_) {
        continue; // skip any corrupted entry rather than crashing
      }
    }
    _entries = entries;
    _loadedAccountKey = account.key;
    notifyListeners();
    // Heal entries recorded before playback carried a poster (their tiles
    // showed the fallback icon forever). Fire-and-forget: the screen shows
    // what it has and repaints when the posters land. The future is kept so
    // tests can await it deterministically.
    lastPosterBackfill = _backfillPosters(account.key);
    unawaited(lastPosterBackfill);
  }

  /// The in-flight (or last) poster backfill kicked off by [loadFor].
  @visibleForTesting
  Future<void>? lastPosterBackfill;

  /// Fills in missing [WatchHistoryEntry.imageUrl]s from the offline catalog:
  /// episodes look up their parent series' cover, movies their poster. Runs
  /// once per load, only over entries that still miss an image, and persists
  /// whatever it finds — so old history heals without a rewatch.
  Future<void> _backfillPosters(String accountKey) async {
    final fixes = <String, String>{}; // entry key -> poster url
    for (final e in List.of(_entries)) {
      if (e.imageUrl != null || e.type == 'live') continue;
      final type = e.type == 'episode' ? ContentType.series : ContentType.movie;
      final id = e.type == 'episode' ? (e.seriesId ?? e.id) : e.id;
      try {
        final row = await CatalogDatabase.instance.itemById(accountKey, type, id);
        final url = row?.imageUrl;
        if (url != null) fixes[e.key] = url;
      } catch (_) {
        return; // no catalog (yet) — try again next load
      }
    }
    // The account may have switched while we were querying.
    if (fixes.isEmpty || _loadedAccountKey != accountKey) return;
    _entries = [
      for (final e in _entries)
        e.imageUrl == null && fixes.containsKey(e.key)
            ? e.withImageUrl(fixes[e.key]!)
            : e,
    ];
    notifyListeners();
    await _persist();
  }

  Future<void> deleteFor(Account account) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKeyFor(account.key));
    if (_loadedAccountKey == account.key) {
      _entries = [];
      _loadedAccountKey = null;
      notifyListeners();
    }
  }

  /// Reads [account]'s stored history as JSON maps for a backup export,
  /// independent of which account is currently loaded.
  Future<List<Map<String, dynamic>>> exportFor(Account account) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKeyFor(account.key)) ?? [];
    final out = <Map<String, dynamic>>[];
    for (final s in raw) {
      try {
        out.add(jsonDecode(s) as Map<String, dynamic>);
      } catch (_) {
        continue;
      }
    }
    return out;
  }

  /// Merges backup [items] into [account]'s history — union by key, existing
  /// entries kept (and kept newest-first), imported ones appended, capped at
  /// [_maxEntries] — and persists. Refreshes memory if [account] is loaded.
  Future<void> importFor(Account account, List<dynamic> items) async {
    final prefs = await SharedPreferences.getInstance();
    final prefsKey = _prefsKeyFor(account.key);
    final merged = <WatchHistoryEntry>[];
    final seen = <String>{};
    void add(WatchHistoryEntry e) {
      if (seen.add(e.key)) merged.add(e);
    }

    for (final s in prefs.getStringList(prefsKey) ?? []) {
      try {
        add(WatchHistoryEntry.fromJson(jsonDecode(s)));
      } catch (_) {
        continue;
      }
    }
    for (final raw in items) {
      if (raw is! Map) continue;
      try {
        add(WatchHistoryEntry.fromJson(raw.cast<String, dynamic>()));
      } catch (_) {
        continue;
      }
    }
    final capped =
        merged.length > _maxEntries ? merged.sublist(0, _maxEntries) : merged;
    await prefs.setStringList(
        prefsKey, capped.map((e) => jsonEncode(e.toJson())).toList());
    if (_loadedAccountKey == account.key) {
      _entries = capped;
      notifyListeners();
    }
  }

  /// Logs that [entry] was just opened. Rewatching something already in
  /// history moves its existing row back to the top instead of piling up
  /// duplicates for the same movie/episode/channel.
  Future<void> record(WatchHistoryEntry entry) async {
    _entries.removeWhere((e) => e.key == entry.key);
    _entries.insert(0, entry);
    if (_entries.length > _maxEntries) {
      _entries = _entries.sublist(0, _maxEntries);
    }
    notifyListeners();
    await _persist();
  }

  /// Removes a single row (e.g. a "remove from history" action on one
  /// entry), as opposed to [clear] which wipes the whole log.
  Future<void> remove(String key) async {
    final before = _entries.length;
    _entries.removeWhere((e) => e.key == key);
    if (_entries.length == before) return;
    notifyListeners();
    await _persist();
  }

  /// Removes every episode entry belonging to [seriesId]. The Series tab
  /// shows one tile per show (collapsed to its latest episode), so removing
  /// just that one entry would leave the tile behind showing an older
  /// episode - this makes "remove" actually clear the whole show.
  Future<void> removeSeries(String seriesId) async {
    final before = _entries.length;
    _entries.removeWhere((e) => e.type == 'episode' && e.seriesId == seriesId);
    if (_entries.length == before) return;
    notifyListeners();
    await _persist();
  }

  Future<void> clear() async {
    _entries = [];
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    final accountKey = _loadedAccountKey;
    if (accountKey == null) return; // nothing loaded yet - nothing to save
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _prefsKeyFor(accountKey),
      _entries.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }
}
