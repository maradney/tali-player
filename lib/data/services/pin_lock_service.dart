import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../db/catalog_database.dart';
import '../models/account.dart';
import 'catalog_sync_service.dart';

/// Parental-control style PIN lock for categories and individual items
/// (live channels, movies, series) across Live TV/Movies/Series. Follows
/// the same singleton/ChangeNotifier/per-account-SharedPreferences shape
/// as FavoritesService/WatchHistoryService.
///
/// Locks are re-checked every time a locked category/item is opened
/// (entering the correct PIN unlocks that one action, not a session) -
/// there's no "stay unlocked" state to track here by design.
class PinLockService extends ChangeNotifier {
  PinLockService._() {
    // A catalog resync can change which category an item belongs to (or
    // fill in the index for the first time) - keep our item->category map
    // fresh so category-level locks stay accurate afterwards.
    CatalogSyncService.instance.addListener(_onCatalogSyncChanged);
  }
  static final PinLockService instance = PinLockService._();

  static String _prefsKeyFor(String accountKey) => 'pin_lock_v1_$accountKey';

  // The PIN is never kept or stored in plaintext - only a salted SHA-256
  // hash lands in shared_preferences, so someone poking around the prefs
  // file on a shared PC can't just read the parental-control PIN out of it.
  //
  // Deliberately NOT a slow KDF: a 4-digit PIN only has 10k candidates, so
  // anyone willing to write a script recovers it from the hash regardless of
  // how the hashing is done. The salt+hash defeats reading it at a glance,
  // which is the threat this control is actually for; treating it as a secret
  // that survives a motivated attacker with local file access would be
  // misleading. Real protection there would need OS-level account separation.
  String? _pinHash;
  String? _pinSalt;
  // Entries are 'type:categoryId' / 'type:id', e.g. 'live:5', 'movie:120'.
  Set<String> _lockedCategories = {};
  Set<String> _lockedItems = {};
  String? _loadedAccountKey;

  // Authoritative 'type:id' -> categoryId map from the search catalog, so a
  // locked category is enforced even for items reached via a snapshot that
  // predates (or never carried) its categoryId - e.g. old favorites/history.
  Map<String, String> _itemCategory = {};
  bool _wasSyncing = false;

  bool get hasPin => _pinHash != null && _pinHash!.isNotEmpty;

  static String _hashPin(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();

  static String _newSalt() {
    final rng = Random.secure();
    return List.generate(
      16,
      (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Future<void> loadFor(Account account) async {
    if (_loadedAccountKey == account.key) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKeyFor(account.key));
    var migratedLegacyPin = false;
    if (raw != null) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        final legacyPin = map['pin'] as String?;
        if (legacyPin != null && legacyPin.isNotEmpty) {
          // Data written before hashing existed stored the PIN in
          // plaintext - convert it on the spot and re-persist below so the
          // plaintext copy is gone after the first load.
          _pinSalt = _newSalt();
          _pinHash = _hashPin(legacyPin, _pinSalt!);
          migratedLegacyPin = true;
        } else {
          _pinHash = map['pinHash'] as String?;
          _pinSalt = map['pinSalt'] as String?;
        }
        _lockedCategories = Set<String>.from(map['lockedCategories'] as List? ?? []);
        _lockedItems = Set<String>.from(map['lockedItems'] as List? ?? []);
      } catch (_) {
        _pinHash = null;
        _pinSalt = null;
        _lockedCategories = {};
        _lockedItems = {};
      }
    } else {
      _pinHash = null;
      _pinSalt = null;
      _lockedCategories = {};
      _lockedItems = {};
    }
    _loadedAccountKey = account.key;
    if (migratedLegacyPin) await _persist();
    _itemCategory = await CatalogDatabase.instance.categoryIndexFor(account.key);
    notifyListeners();
  }

  void _onCatalogSyncChanged() {
    final syncing = CatalogSyncService.instance.isSyncing;
    // Only act on the syncing -> idle edge (a sync just finished), not the
    // many progress notifications in between.
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
      _pinHash = null;
      _pinSalt = null;
      _lockedCategories = {};
      _lockedItems = {};
      _loadedAccountKey = null;
      notifyListeners();
    }
  }

  bool verifyPin(String input) =>
      hasPin && _pinSalt != null && _hashPin(input, _pinSalt!) == _pinHash;

  Future<void> setPin(String pin) async {
    _pinSalt = _newSalt();
    _pinHash = _hashPin(pin, _pinSalt!);
    notifyListeners();
    await _persist();
  }

  /// Removing the PIN also clears every lock - a lock nobody can ever
  /// enter a PIN to open again would just be permanently hidden content.
  Future<void> clearPin() async {
    _pinHash = null;
    _pinSalt = null;
    _lockedCategories.clear();
    _lockedItems.clear();
    notifyListeners();
    await _persist();
  }

  bool isCategoryLocked(String type, String categoryId) =>
      _lockedCategories.contains('$type:$categoryId');

  bool isItemLocked(String type, String id) => _lockedItems.contains('$type:$id');

  /// The set of locked-category keys ('type:categoryId'), for surfaces that
  /// need to exclude a whole locked category up front (e.g. Browse hiding
  /// locked-category titles from its genre facets) rather than gating each
  /// item on open. A copy, so callers can't mutate the lock set.
  Set<String> get lockedCategoryKeys => Set.unmodifiable(_lockedCategories);

  /// Whether [id]'s *category* is locked, ignoring any item-level lock —
  /// resolving the category from the caller's hint or the catalog index, the
  /// same way [isLocked] does. Lets a surface hide content that belongs to a
  /// locked category while still showing individually-locked items (which stay
  /// visible, obscured, and gated by a PIN on open).
  bool isCategoryLockedForItem(String type, String id, {String? categoryId}) {
    final resolved = (categoryId != null && categoryId.isNotEmpty)
        ? categoryId
        : _itemCategory['$type:$id'];
    return resolved != null && isCategoryLocked(type, resolved);
  }

  /// True if the item itself is locked, or it belongs to a locked category.
  ///
  /// [categoryId] is the caller's best guess (from a snapshot that may or
  /// may not carry it); when null/absent, we fall back to the catalog index
  /// so a locked category is enforced even for a snapshot that never stored
  /// its category - e.g. a favorite saved before this data was tracked.
  bool isLocked(String type, String id, {String? categoryId}) {
    if (isItemLocked(type, id)) return true;
    final resolvedCategoryId =
        (categoryId != null && categoryId.isNotEmpty)
            ? categoryId
            : _itemCategory['$type:$id'];
    if (resolvedCategoryId != null && isCategoryLocked(type, resolvedCategoryId)) {
      return true;
    }
    return false;
  }

  Future<void> setCategoryLocked(String type, String categoryId, bool locked) async {
    final key = '$type:$categoryId';
    if (locked) {
      _lockedCategories.add(key);
    } else {
      _lockedCategories.remove(key);
    }
    notifyListeners();
    await _persist();
  }

  Future<void> setItemLocked(String type, String id, bool locked) async {
    final key = '$type:$id';
    if (locked) {
      _lockedItems.add(key);
    } else {
      _lockedItems.remove(key);
    }
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    final accountKey = _loadedAccountKey;
    if (accountKey == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKeyFor(accountKey),
      jsonEncode({
        'pinHash': _pinHash,
        'pinSalt': _pinSalt,
        'lockedCategories': _lockedCategories.toList(),
        'lockedItems': _lockedItems.toList(),
      }),
    );
  }
}
