import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../db/catalog_database.dart';
import '../models/account.dart';
import 'catalog_sync_service.dart';
import 'profiles_service.dart';

/// The content allowlist for a "kids" profile: a default-deny filter that hides
/// every category *except* the ones a parent explicitly permits. Unlike
/// [PinLockService] (which shows a locked category behind a PIN gate), a
/// category the allowlist doesn't include is removed from view entirely — a
/// child in a kids profile never sees it and there's no PIN prompt to reveal
/// it.
///
/// Per-account like the other services (key carries the profile-id prefix, so
/// the allowlist is naturally per-profile-per-playlist). Enforcement is gated
/// on whether the **active profile** is a kids profile ([Profile.isKids]) —
/// there is no separate on/off flag to forget, so a kids profile is
/// safe-by-default: with nothing yet allowed it shows *nothing*, and a normal
/// profile is never affected (every predicate reports "visible"). The parallel
/// to [PinLockService]'s shape is deliberate: the same screens consult both.
class KidsFilterService extends ChangeNotifier {
  KidsFilterService._() {
    // A resync can change which category an item belongs to (or index it for
    // the first time) — keep the item->category map fresh so the allowlist
    // stays accurate for items reached via denormalized snapshots.
    CatalogSyncService.instance.addListener(_onCatalogSyncChanged);
  }
  static final KidsFilterService instance = KidsFilterService._();

  static String _prefsKeyFor(String accountKey) => 'kids_filter_v1_$accountKey';

  /// Allowed category keys, 'type:categoryId' (e.g. 'live:5', 'movie:120') —
  /// same shape as PinLockService's lock keys.
  Set<String> _allowed = {};
  String? _loadedAccountKey;

  /// Authoritative 'type:id' -> categoryId map from the catalog, so the
  /// allowlist is enforced even for an item reached via a snapshot that
  /// predates (or never carried) its categoryId — e.g. old favorites/history.
  Map<String, String> _itemCategory = {};
  bool _wasSyncing = false;

  /// Whether the filter is actively restricting: true exactly when the active
  /// profile is a kids profile. There is deliberately no persisted "enabled"
  /// flag — tying enforcement to [Profile.isKids] removes the drift where a
  /// kids profile could sit unrestricted because a toggle was never flipped.
  bool get isRestricting =>
      ProfilesService.instance.activeProfile?.isKids ?? false;

  Future<void> loadFor(Account account) async {
    if (_loadedAccountKey == account.key) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKeyFor(account.key));
    if (raw != null) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        _allowed = Set<String>.from(map['allowed'] as List? ?? []);
      } catch (_) {
        _allowed = {};
      }
    } else {
      _allowed = {};
    }
    _loadedAccountKey = account.key;
    _itemCategory = await CatalogDatabase.instance.categoryIndexFor(account.key);
    notifyListeners();
  }

  void _onCatalogSyncChanged() {
    final syncing = CatalogSyncService.instance.isSyncing;
    // Only act on the syncing -> idle edge (a sync just finished).
    if (_wasSyncing && !syncing) {
      final accountKey = _loadedAccountKey;
      if (accountKey != null) {
        CatalogDatabase.instance.categoryIndexFor(accountKey).then((index) {
          _itemCategory = index;
          notifyListeners();
        });
      }
    }
    _wasSyncing = syncing;
  }

  Future<void> deleteFor(Account account) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKeyFor(account.key));
    if (_loadedAccountKey == account.key) {
      _allowed = {};
      _loadedAccountKey = null;
      notifyListeners();
    }
  }

  /// Whether [categoryId] of [type] is hidden for the current profile — true
  /// when a kids profile is active and the category isn't on the allowlist.
  bool isCategoryHidden(String type, String categoryId) =>
      isRestricting && !_allowed.contains('$type:$categoryId');

  /// Whether an item is hidden because its *category* isn't allowed. Resolves
  /// the category from the caller's hint or the catalog index, mirroring
  /// [PinLockService.isCategoryLockedForItem].
  bool isHiddenForItem(String type, String id, {String? categoryId}) {
    if (!isRestricting) return false;
    final resolved = (categoryId != null && categoryId.isNotEmpty)
        ? categoryId
        : _itemCategory['$type:$id'];
    // A category we can't resolve is hidden under default-deny: better to hide
    // an unclassifiable item in a kids profile than to leak it.
    if (resolved == null) return true;
    return isCategoryHidden(type, resolved);
  }

  /// True if [type]'s [categoryId] is on the allowlist (regardless of whether a
  /// kids profile is active) — for the curation UI's checkbox state.
  bool isAllowed(String type, String categoryId) =>
      _allowed.contains('$type:$categoryId');

  /// The allowed-category keys ('type:categoryId'), for SQL aggregates that
  /// can't be post-filtered per row (search-count badges, genre facets). Null
  /// when no kids profile is active — callers pass it straight through and a
  /// null means "no restriction". A copy, so callers can't mutate the set.
  Set<String>? get allowedCategoryKeysOrNull =>
      isRestricting ? Set.unmodifiable(_allowed) : null;

  Future<void> setAllowed(String type, String categoryId, bool allowed) async {
    final key = '$type:$categoryId';
    if (allowed) {
      _allowed.add(key);
    } else {
      _allowed.remove(key);
    }
    notifyListeners();
    await _persist();
  }

  /// The stored allowlist for [account] as a JSON map, for backup export —
  /// independent of which account is loaded. Null when nothing is stored.
  Future<Map<String, dynamic>?> exportFor(Account account) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKeyFor(account.key));
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Restores a backed-up allowlist for [account]. Replaces any existing one.
  /// (A legacy backup may also carry an `enabled` flag; it's ignored now that
  /// enforcement follows [Profile.isKids].)
  Future<void> importFor(Account account, Map<String, dynamic> data) async {
    final allowed = List<String>.from(data['allowed'] as List? ?? []);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _prefsKeyFor(account.key), jsonEncode({'allowed': allowed}));
    if (_loadedAccountKey == account.key) {
      _allowed = allowed.toSet();
      notifyListeners();
    }
  }

  Future<void> _persist() async {
    final accountKey = _loadedAccountKey;
    if (accountKey == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKeyFor(accountKey),
      jsonEncode({'allowed': _allowed.toList()}),
    );
  }

  @visibleForTesting
  Future<void> resetForTesting() async {
    _allowed = {};
    _loadedAccountKey = null;
    _itemCategory = {};
    _wasSyncing = false;
  }
}
