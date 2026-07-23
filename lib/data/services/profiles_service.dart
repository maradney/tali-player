import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/profile.dart';

/// Singleton store of user [Profile]s — the top layer above playlists — and
/// which one is active. Same ChangeNotifier + shared_preferences shape as
/// AccountsService/FavoritesService.
///
/// The active profile's [Profile.id] is the scope prefix for every piece of
/// per-profile local data (accounts, favorites, history, playback, channel
/// and PIN prefs, and appearance settings), so switching profiles swaps the
/// entire app to an isolated data set.
///
/// There is always at least one profile: [load] seeds a default one if none
/// exist (fresh install), and [removeProfile] re-seeds one if the last is
/// deleted, so callers never have to handle a "no active profile" state.
class ProfilesService extends ChangeNotifier {
  ProfilesService._();
  static final ProfilesService instance = ProfilesService._();

  /// Well-known id of the starter profile — the one the upgrade migration
  /// assigns existing playlists/data to, and the one [load] seeds on a fresh
  /// install. Kept stable so migrated data keys line up.
  static const String defaultProfileId = 'default';
  static const String defaultProfileName = 'Default';

  static const _profilesKey = 'profiles_v1';
  static const _activeProfileKey = 'active_profile_id_v1';

  List<Profile> _profiles = [];
  String? _activeId;
  bool _loaded = false;

  List<Profile> get profiles => List.unmodifiable(_profiles);

  String? get activeProfileId => _activeId;

  Profile? get activeProfile {
    if (_activeId == null) return null;
    for (final p in _profiles) {
      if (p.id == _activeId) return p;
    }
    return null;
  }

  @visibleForTesting
  void resetForTesting() {
    _profiles = [];
    _activeId = null;
    _loaded = false;
  }

  // The PIN is never kept in plaintext — only a salted SHA-256 hash lands in
  // prefs. Mirrors PinLockService's hashing so both features behave the same,
  // including its documented limit: this stops a PIN being *read*, not a short
  // one being brute-forced offline. See PinLockService for the reasoning.
  static String _hashPin(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();

  static String _newSalt() {
    final rng = Random.secure();
    return List.generate(
      16,
      (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  static String _generateId() {
    final rng = Random.secure();
    return 'profile_${DateTime.now().microsecondsSinceEpoch}_'
        '${rng.nextInt(1 << 32).toRadixString(16)}';
  }

  /// Call once at startup, before runApp(), after any upgrade migration so
  /// the migrated default profile is picked up. Seeds a default profile when
  /// none are saved so there is always an active profile.
  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_profilesKey) ?? [];
    final profiles = <Profile>[];
    for (final s in raw) {
      try {
        profiles.add(Profile.fromJson(jsonDecode(s) as Map<String, dynamic>));
      } catch (_) {
        continue; // skip a corrupted entry rather than crashing
      }
    }
    _profiles = profiles;
    _activeId = prefs.getString(_activeProfileKey);

    if (_profiles.isEmpty) {
      // Fresh install (or everything was corrupt) — seed the starter profile
      // so the rest of the app always has a scope to key data under.
      _profiles = [
        const Profile(id: defaultProfileId, name: defaultProfileName),
      ];
      _activeId = defaultProfileId;
      _loaded = true;
      await _persist();
      notifyListeners();
      return;
    }

    // Keep the active id pointing at a real profile.
    if (activeProfile == null) _activeId = _profiles.first.id;
    _loaded = true;
    notifyListeners();
  }

  /// Adds a new profile (optionally PIN-protected) and makes it active.
  /// Returns the created profile. [isKids] marks it as a content-restricted
  /// kids profile; such profiles are intentionally left PIN-less.
  Future<Profile> addProfile(
      {required String name, String? pin, bool isKids = false}) async {
    String? hash;
    String? salt;
    if (pin != null && pin.isNotEmpty) {
      salt = _newSalt();
      hash = _hashPin(pin, salt);
    }
    final profile = Profile(
      id: _generateId(),
      name: name,
      pinHash: hash,
      pinSalt: salt,
      isKids: isKids,
    );
    _profiles.add(profile);
    _activeId = profile.id;
    notifyListeners();
    await _persist();
    return profile;
  }

  Future<void> renameProfile(String id, String name) async {
    final i = _profiles.indexWhere((p) => p.id == id);
    if (i < 0) return;
    _profiles[i] = _profiles[i].copyWith(name: name);
    notifyListeners();
    await _persist();
  }

  Future<void> setPin(String id, String pin) async {
    final i = _profiles.indexWhere((p) => p.id == id);
    if (i < 0) return;
    final salt = _newSalt();
    _profiles[i] = _profiles[i].copyWith(
      pinHash: _hashPin(pin, salt),
      pinSalt: salt,
    );
    notifyListeners();
    await _persist();
  }

  Future<void> clearPin(String id) async {
    final i = _profiles.indexWhere((p) => p.id == id);
    if (i < 0) return;
    _profiles[i] = _profiles[i].copyWith(clearPin: true);
    notifyListeners();
    await _persist();
  }

  bool verifyPin(String id, String input) {
    final i = _profiles.indexWhere((p) => p.id == id);
    if (i < 0) return false;
    final p = _profiles[i];
    return p.hasPin && p.pinSalt != null && _hashPin(input, p.pinSalt!) == p.pinHash;
  }

  Future<void> switchTo(String id) async {
    if (_activeId == id) return;
    if (!_profiles.any((p) => p.id == id)) return;
    _activeId = id;
    notifyListeners();
    await _persist();
  }

  /// Removes a profile from the list and fixes up the active id. Does NOT
  /// tear down the profile's playlists/data — that cascade is orchestrated by
  /// the caller (which owns the per-account + settings services). Re-seeds a
  /// default profile if the last one was removed so there is always an active
  /// profile.
  Future<void> removeProfile(String id) async {
    _profiles.removeWhere((p) => p.id == id);
    if (_profiles.isEmpty) {
      _profiles = [
        const Profile(id: defaultProfileId, name: defaultProfileName),
      ];
      _activeId = defaultProfileId;
    } else if (_activeId == id) {
      _activeId = _profiles.first.id;
    }
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _profilesKey,
      _profiles.map((p) => jsonEncode(p.toJson())).toList(),
    );
    if (_activeId == null) {
      await prefs.remove(_activeProfileKey);
    } else {
      await prefs.setString(_activeProfileKey, _activeId!);
    }
  }
}
