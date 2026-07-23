import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/account.dart';
import '../models/favorite_item.dart';

/// Singleton so every screen shares the same list and rebuilds when it
/// changes, without needing a DI framework. `ChangeNotifier` lets widgets
/// listen via AnimatedBuilder/ListenableBuilder.
///
/// Favorites are namespaced per account (each playlist has its own list),
/// so switching the active account reloads a different stored list rather
/// than mixing favorites from different servers together.
class FavoritesService extends ChangeNotifier {
  FavoritesService._();
  static final FavoritesService instance = FavoritesService._();

  static String _prefsKeyFor(String accountKey) => 'favorites_v1_$accountKey';

  List<FavoriteItem> _items = [];
  String? _loadedAccountKey;

  List<FavoriteItem> get items => List.unmodifiable(_items);

  /// Loads the favorites list for [account]. Safe to call repeatedly (e.g.
  /// on every HomeShell rebuild) - it's a no-op if that account's list is
  /// already loaded.
  Future<void> loadFor(Account account) async {
    if (_loadedAccountKey == account.key) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKeyFor(account.key)) ?? [];
    _items = raw
        .map((s) {
          try {
            return FavoriteItem.fromJson(jsonDecode(s));
          } catch (_) {
            return null; // skip any corrupted entry rather than crashing
          }
        })
        .whereType<FavoriteItem>()
        .toList();
    _loadedAccountKey = account.key;
    notifyListeners();
  }

  /// Deletes a removed account's saved favorites from disk.
  Future<void> deleteFor(Account account) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKeyFor(account.key));
    if (_loadedAccountKey == account.key) {
      _items = [];
      _loadedAccountKey = null;
      notifyListeners();
    }
  }

  /// Reads [account]'s stored favorites as JSON maps for a backup export,
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

  /// Merges backup [items] into [account]'s favorites — union by key, existing
  /// entries kept, nothing removed — and persists. Refreshes the in-memory
  /// list if [account] is the one currently loaded.
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

  bool isFavorite(String type, String id) =>
      _items.any((i) => i.type == type && i.id == id);

  Future<void> toggle(FavoriteItem item) async {
    if (isFavorite(item.type, item.id)) {
      _items.removeWhere((i) => i.type == item.type && i.id == item.id);
    } else {
      _items.add(item);
    }
    notifyListeners();
    await _persist();
  }

  /// Moves the favorite at index [from] to index [to] *within its own type*
  /// (Live/Movies/Series each reorder independently), persisting the new order.
  /// Items of other types keep their positions: the type's items are rewritten
  /// in the new order into the slots they already occupied in the full list, so
  /// the stored order stays stable for everyone else. Indices are into the
  /// filtered per-type list the UI shows, with `to` already adjusted for the
  /// removal (the ReorderableListView convention is applied by the caller).
  Future<void> reorder(String type, int from, int to) async {
    final typed = _items.where((i) => i.type == type).toList();
    if (from < 0 || from >= typed.length) return;
    to = to.clamp(0, typed.length - 1);
    if (from == to) return;
    final moved = typed.removeAt(from);
    typed.insert(to, moved);
    var t = 0;
    _items = [
      for (final item in _items) if (item.type == type) typed[t++] else item,
    ];
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