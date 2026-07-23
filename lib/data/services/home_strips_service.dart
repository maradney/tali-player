import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/account.dart';
import '../models/home_strip.dart';
import '../models/search_result.dart';

/// Which rails the Home dashboard shows, and in what order — user-customized
/// via the Home "customize" sheet. Backed like [WatchlistService]: per-account
/// (category strips reference account-specific category ids, and the account
/// key's profile-id prefix isolates profiles), wiped with the playlist.
class HomeStripsService extends ChangeNotifier {
  HomeStripsService._();
  static final HomeStripsService instance = HomeStripsService._();

  static String _prefsKeyFor(String accountKey) =>
      'home_strips_v1_$accountKey';

  List<HomeStrip> _strips = HomeStrip.defaults;
  String? _loadedAccountKey;

  /// Current strips in display order (disabled ones included — the dashboard
  /// filters, the editor shows everything).
  List<HomeStrip> get strips => List.unmodifiable(_strips);

  /// Only what the dashboard should render.
  List<HomeStrip> get enabledStrips =>
      List.unmodifiable(_strips.where((s) => s.enabled));

  Future<void> loadFor(Account account) async {
    if (_loadedAccountKey == account.key) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKeyFor(account.key)) ?? [];
    final stored = raw
        .map((s) {
          try {
            return HomeStrip.fromJson(jsonDecode(s) as Map<String, dynamic>);
          } catch (_) {
            return null; // skip a corrupted entry rather than crashing
          }
        })
        .whereType<HomeStrip>()
        .toList();
    _strips = HomeStrip.withDefaults(stored);
    _loadedAccountKey = account.key;
    notifyListeners();
  }

  /// Replaces the whole configuration (the editor's reorder result).
  Future<void> setStrips(List<HomeStrip> strips) async {
    _strips = List.of(strips);
    notifyListeners();
    await _persist();
  }

  Future<void> toggle(String key) async {
    _strips = [
      for (final s in _strips)
        s.key == key ? s.copyWith(enabled: !s.enabled) : s,
    ];
    notifyListeners();
    await _persist();
  }

  /// Appends a rail for one catalog category (no-op if it's already there).
  Future<void> addCategory({
    required ContentType type,
    required String categoryId,
    required String categoryName,
  }) async {
    final strip = HomeStrip(
      type: HomeStripType.category,
      categoryType: type,
      categoryId: categoryId,
      categoryName: categoryName,
    );
    if (_strips.any((s) => s.key == strip.key)) return;
    _strips = [..._strips, strip];
    notifyListeners();
    await _persist();
  }

  /// Removes a category strip. Built-in strips can only be disabled, never
  /// removed — [HomeStrip.withDefaults] would just resurrect them anyway.
  Future<void> remove(String key) async {
    _strips = _strips
        .where((s) => s.type != HomeStripType.category || s.key != key)
        .toList();
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    final accountKey = _loadedAccountKey;
    if (accountKey == null) return; // nothing loaded yet - nothing to save
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _prefsKeyFor(accountKey),
      _strips.map((s) => jsonEncode(s.toJson())).toList(),
    );
  }

  /// Deletes a removed account's strip configuration from disk.
  Future<void> deleteFor(Account account) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKeyFor(account.key));
    if (_loadedAccountKey == account.key) {
      _strips = HomeStrip.defaults;
      _loadedAccountKey = null;
      notifyListeners();
    }
  }

  /// Reads [account]'s stored configuration for a backup export.
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

  /// Restores a backup's configuration. Unlike list-shaped data (favorites),
  /// this is one ordered layout, not a mergeable set — the import replaces the
  /// stored config, but only when the backup actually carries one.
  Future<void> importFor(Account account, List<dynamic> stripsJson) async {
    if (stripsJson.isEmpty) return;
    final imported = stripsJson
        .map((raw) {
          if (raw is! Map) return null;
          try {
            return HomeStrip.fromJson(raw.cast<String, dynamic>());
          } catch (_) {
            return null;
          }
        })
        .whereType<HomeStrip>()
        .toList();
    if (imported.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _prefsKeyFor(account.key),
      imported.map((s) => jsonEncode(s.toJson())).toList(),
    );
    if (_loadedAccountKey == account.key) {
      _strips = HomeStrip.withDefaults(imported);
      notifyListeners();
    }
  }
}
