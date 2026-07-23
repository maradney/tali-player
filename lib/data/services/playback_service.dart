import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/account.dart';
import '../models/playback_progress.dart';

/// Singleton store of per-item playback positions (movies/episodes), so
/// the player can offer to resume and a series' detail screen can jump to
/// the last-watched season/episode. Same ChangeNotifier + per-account
/// shared_preferences pattern as FavoritesService.
class PlaybackService extends ChangeNotifier {
  PlaybackService._();
  static final PlaybackService instance = PlaybackService._();

  static String _prefsKeyFor(String accountKey) => 'playback_v1_$accountKey';

  Map<String, PlaybackProgress> _items = {};
  String? _loadedAccountKey;

  Future<void> loadFor(Account account) async {
    if (_loadedAccountKey == account.key) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKeyFor(account.key)) ?? [];
    final items = <String, PlaybackProgress>{};
    for (final s in raw) {
      try {
        final progress = PlaybackProgress.fromJson(jsonDecode(s));
        items[progress.key] = progress;
      } catch (_) {
        continue; // skip any corrupted entry rather than crashing
      }
    }
    _items = items;
    _loadedAccountKey = account.key;
    notifyListeners();
  }

  Future<void> deleteFor(Account account) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKeyFor(account.key));
    if (_loadedAccountKey == account.key) {
      _items = {};
      _loadedAccountKey = null;
      notifyListeners();
    }
  }

  /// Reads [account]'s stored resume positions as JSON maps for a backup
  /// export, independent of which account is currently loaded.
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

  /// Merges backup [items] into [account]'s resume positions — keyed by item,
  /// existing positions kept on a collision, nothing removed — and persists.
  /// Refreshes memory if [account] is the one currently loaded.
  Future<void> importFor(Account account, List<dynamic> items) async {
    final prefs = await SharedPreferences.getInstance();
    final prefsKey = _prefsKeyFor(account.key);
    final merged = <String, PlaybackProgress>{};
    for (final s in prefs.getStringList(prefsKey) ?? []) {
      try {
        final p = PlaybackProgress.fromJson(jsonDecode(s));
        merged[p.key] = p;
      } catch (_) {
        continue;
      }
    }
    for (final raw in items) {
      if (raw is! Map) continue;
      try {
        final p = PlaybackProgress.fromJson(raw.cast<String, dynamic>());
        merged.putIfAbsent(p.key, () => p);
      } catch (_) {
        continue;
      }
    }
    await prefs.setStringList(
        prefsKey, merged.values.map((p) => jsonEncode(p.toJson())).toList());
    if (_loadedAccountKey == account.key) {
      _items = merged;
      notifyListeners();
    }
  }

  PlaybackProgress? progressFor(String type, String id) => _items['$type:$id'];

  /// Whether this item has any tracked playback position - used to show a
  /// "continue watching" badge in grids, favorites, and search results.
  /// Series are checked via [lastEpisodeForSeries] since progress is
  /// tracked per-episode, not per-series.
  bool isInProgress(String type, String id) {
    if (type == 'series') return lastEpisodeForSeries(id) != null;
    return progressFor(type, id) != null;
  }

  /// How far into the tracked position this item is (0-1), or null if
  /// nothing's tracked - drives the "continue watching" progress bar. For
  /// series this is progress within the last-watched episode, since
  /// there's no single meaningful fraction for a multi-episode show.
  double? progressFraction(String type, String id) {
    final p = type == 'series' ? lastEpisodeForSeries(id) : progressFor(type, id);
    if (p == null || p.total == Duration.zero) return null;
    return p.position.inMilliseconds / p.total.inMilliseconds;
  }

  /// Most recently watched episode for a series, or null if none tracked -
  /// used to jump the series detail screen to the right season/episode.
  PlaybackProgress? lastEpisodeForSeries(String seriesId) {
    PlaybackProgress? latest;
    for (final p in _items.values) {
      if (p.type == 'episode' && p.seriesId == seriesId) {
        if (latest == null || p.updatedAt.isAfter(latest.updatedAt)) latest = p;
      }
    }
    return latest;
  }

  Future<void> save(PlaybackProgress progress) async {
    _items[progress.key] = progress;
    notifyListeners();
    await _persist();
  }

  Future<void> clear(String type, String id) async {
    final removed = _items.remove('$type:$id');
    if (removed == null) return;
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    final accountKey = _loadedAccountKey;
    if (accountKey == null) return; // nothing loaded yet - nothing to save
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _prefsKeyFor(accountKey),
      _items.values.map((p) => jsonEncode(p.toJson())).toList(),
    );
  }
}
