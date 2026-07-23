import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/account.dart';
import '../models/favorite_item.dart';

/// The "watch later" queue — a saved list of movies/series the user means to
/// get to, distinct from Favorites (curated "want to keep") and Watch History
/// (already opened). Backed exactly like [FavoritesService]: a per-account list
/// of [FavoriteItem] snapshots (which is just a denormalized content pointer),
/// namespaced by account key so each playlist — and each profile, via the
/// profile-id prefix on the key — keeps its own queue.
///
/// Scoped to movies and series; live channels are "on now", not "watch later".
class WatchlistService extends ChangeNotifier {
  WatchlistService._();
  static final WatchlistService instance = WatchlistService._();

  static String _prefsKeyFor(String accountKey) => 'watchlist_v1_$accountKey';

  List<FavoriteItem> _items = [];
  String? _loadedAccountKey;

  List<FavoriteItem> get items => List.unmodifiable(_items);

  /// Loads the watchlist for [account]. A no-op if that account's list is
  /// already the one in memory, so it's safe to call on every shell rebuild.
  Future<void> loadFor(Account account) async {
    if (_loadedAccountKey == account.key) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKeyFor(account.key)) ?? [];
    _items = raw
        .map((s) {
          try {
            return FavoriteItem.fromJson(jsonDecode(s));
          } catch (_) {
            return null; // skip a corrupted entry rather than crashing
          }
        })
        .whereType<FavoriteItem>()
        .toList();
    _loadedAccountKey = account.key;
    notifyListeners();
  }

  /// Deletes a removed account's saved watchlist from disk.
  Future<void> deleteFor(Account account) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKeyFor(account.key));
    if (_loadedAccountKey == account.key) {
      _items = [];
      _loadedAccountKey = null;
      notifyListeners();
    }
  }

  /// Reads [account]'s stored watchlist as JSON maps for a backup export,
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

  /// Merges backup [items] into [account]'s watchlist — union by key, existing
  /// entries kept, nothing removed — and persists. Refreshes the in-memory list
  /// if [account] is the one currently loaded.
  Future<void> importFor(Account account, List<dynamic> items) async {
    final prefs = await SharedPreferences.getInstance();
    final prefsKey = _prefsKeyFor(account.key);
    final merged = <FavoriteItem>[];
    final seen = <String>{};
    void add(FavoriteItem f) {
      if (seen.add(f.key)) merged.add(f);
    }

    for (final s in prefs.getStringList(prefsKey) ?? []) {
      try {
        add(FavoriteItem.fromJson(jsonDecode(s)));
      } catch (_) {
        continue;
      }
    }
    for (final raw in items) {
      if (raw is! Map) continue;
      try {
        add(FavoriteItem.fromJson(raw.cast<String, dynamic>()));
      } catch (_) {
        continue;
      }
    }
    await prefs.setStringList(
        prefsKey, merged.map((f) => jsonEncode(f.toJson())).toList());
    if (_loadedAccountKey == account.key) {
      _items = merged;
      notifyListeners();
    }
  }

  bool isInWatchlist(String type, String id) =>
      _items.any((i) => i.type == type && i.id == id);

  /// Adds [item] if absent, removes it if present. New items are appended, so
  /// the stored order is oldest-first (surfaces reverse it to show the most
  /// recently added at the front of the queue).
  Future<void> toggle(FavoriteItem item) async {
    if (isInWatchlist(item.type, item.id)) {
      _items.removeWhere((i) => i.type == item.type && i.id == item.id);
    } else {
      _items.add(item);
    }
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    final accountKey = _loadedAccountKey;
    if (accountKey == null) return; // nothing loaded yet - nothing to save
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _prefsKeyFor(accountKey),
      _items.map((i) => jsonEncode(i.toJson())).toList(),
    );
  }
}
