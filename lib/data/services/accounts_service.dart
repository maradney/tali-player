import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/account.dart';
import 'profiles_service.dart';

/// Singleton store of saved playlists (accounts) and which one is active.
/// Account metadata (profile/name/server/username) lives in
/// shared_preferences, same ChangeNotifier pattern as FavoritesService.
/// Passwords are kept out of that plaintext JSON and stored separately via
/// flutter_secure_storage (Windows DPAPI / Keychain / Keystore).
///
/// Every playlist belongs to a [profileId]. This service holds *all* profiles'
/// playlists but the public [accounts]/[activeAccount] surface is scoped to
/// the profile that's currently active in [ProfilesService], and the active
/// playlist is tracked per profile so switching profiles restores the playlist
/// you were last on. It listens to ProfilesService so a profile switch
/// re-notifies its own listeners (e.g. HomeShell) in place.
class AccountsService extends ChangeNotifier {
  AccountsService._();
  static final AccountsService instance = AccountsService._();

  static const _accountsKey = 'accounts_v1';
  static const _activeKeysKey = 'active_account_keys_v1'; // {profileId: key}
  static const _legacyActiveKeyKey = 'active_account_key_v1'; // pre-profiles
  static const _secureStorage = FlutterSecureStorage();

  static String _passwordKeyFor(String accountKey) =>
      'account_password_$accountKey';

  List<Account> _accounts = [];
  Map<String, String> _activeKeyByProfile = {};
  bool _loaded = false;
  bool _listeningToProfiles = false;

  /// All playlists across every profile (unfiltered). Rarely needed directly —
  /// prefer [accounts]. Used by the profile-delete cascade.
  List<Account> get allAccounts => List.unmodifiable(_accounts);

  /// Playlists belonging to the currently active profile.
  List<Account> get accounts {
    final profileId = ProfilesService.instance.activeProfileId;
    return List.unmodifiable(
      _accounts.where((a) => a.profileId == profileId),
    );
  }

  @visibleForTesting
  void resetForTesting() {
    _accounts = [];
    _activeKeyByProfile = {};
    _loaded = false;
  }

  /// The active playlist within the active profile: the one last switched to
  /// for this profile if it still exists, otherwise the profile's first
  /// playlist, otherwise null (profile has no playlists yet).
  Account? get activeAccount {
    final profileId = ProfilesService.instance.activeProfileId;
    if (profileId == null) return null;
    final inProfile = _accounts.where((a) => a.profileId == profileId).toList();
    if (inProfile.isEmpty) return null;
    final wantedKey = _activeKeyByProfile[profileId];
    for (final a in inProfile) {
      if (a.key == wantedKey) return a;
    }
    return inProfile.first;
  }

  /// Call once at app startup, before runApp(), after ProfilesService.load()
  /// so the active profile is known.
  Future<void> load() async {
    if (!_listeningToProfiles) {
      ProfilesService.instance.addListener(_onProfileChanged);
      _listeningToProfiles = true;
    }
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_accountsKey) ?? [];

    // Older saves kept the password inline in this same JSON. If we find
    // one, migrate it into secure storage below rather than losing it.
    var needsMigration = false;
    final accounts = <Account>[];
    for (final s in raw) {
      try {
        final json = jsonDecode(s) as Map<String, dynamic>;
        final inlinePassword = json['password'] as String?;
        if (inlinePassword != null) {
          needsMigration = true;
          accounts.add(Account.fromMetaJson(json, password: inlinePassword));
          continue;
        }
        final metaOnly = Account.fromMetaJson(json, password: '');
        final stored =
            await _secureStorage.read(key: _passwordKeyFor(metaOnly.key));
        if (stored == null) continue; // no password on record - drop it
        accounts.add(Account.fromMetaJson(json, password: stored));
      } catch (_) {
        continue; // skip any corrupted entry rather than crashing
      }
    }
    _accounts = accounts;
    _activeKeyByProfile = _readActiveKeys(prefs);
    _loaded = true;
    notifyListeners();
    // Rewrites the metadata list without inline passwords and seeds
    // secure storage for anything migrated above.
    if (needsMigration) await _persist();
  }

  Map<String, String> _readActiveKeys(SharedPreferences prefs) {
    final raw = prefs.getString(_activeKeysKey);
    if (raw != null) {
      try {
        return (jsonDecode(raw) as Map<String, dynamic>).cast<String, String>();
      } catch (_) {
        // fall through to legacy handling
      }
    }
    // Pre-profiles single active key → attribute it to the account's profile.
    final legacy = prefs.getString(_legacyActiveKeyKey);
    if (legacy != null) {
      final match = _accounts.where((a) => a.key == legacy);
      if (match.isNotEmpty) return {match.first.profileId: legacy};
    }
    return {};
  }

  void _onProfileChanged() {
    // The filtered getters recompute against the new active profile; just
    // wake our listeners so the shell rebuilds for the new profile's data.
    notifyListeners();
  }

  /// Adds a new playlist, or updates it in place if the same key already
  /// exists (e.g. re-entering credentials after a password change). Makes it
  /// the active playlist for its profile.
  Future<void> addAccount(Account account) async {
    _accounts.removeWhere((a) => a.key == account.key);
    _accounts.add(account);
    _activeKeyByProfile[account.profileId] = account.key;
    notifyListeners();
    await _persist();
  }

  /// Switches the active playlist within the active profile. Ignores keys that
  /// don't belong to a known account.
  Future<void> switchTo(String accountKey) async {
    final match = _accounts.where((a) => a.key == accountKey);
    if (match.isEmpty) return;
    final account = match.first;
    if (_activeKeyByProfile[account.profileId] == accountKey) return;
    _activeKeyByProfile[account.profileId] = accountKey;
    notifyListeners();
    await _persist();
  }

  Future<void> removeAccount(String accountKey) async {
    final match = _accounts.where((a) => a.key == accountKey).toList();
    if (match.isEmpty) return;
    final profileId = match.first.profileId;
    _accounts.removeWhere((a) => a.key == accountKey);
    if (_activeKeyByProfile[profileId] == accountKey) {
      final remaining = _accounts.where((a) => a.profileId == profileId);
      if (remaining.isEmpty) {
        _activeKeyByProfile.remove(profileId);
      } else {
        _activeKeyByProfile[profileId] = remaining.first.key;
      }
    }
    notifyListeners();
    await _secureStorage.delete(key: _passwordKeyFor(accountKey));
    await _persist();
  }

  /// Removes every playlist belonging to [profileId] and returns them, so the
  /// caller can tear down each one's per-account local data (favorites,
  /// history, playback, PIN/channel prefs, catalog). Part of the
  /// delete-profile cascade.
  Future<List<Account>> removeAccountsForProfile(String profileId) async {
    final removed = _accounts.where((a) => a.profileId == profileId).toList();
    _accounts.removeWhere((a) => a.profileId == profileId);
    _activeKeyByProfile.remove(profileId);
    notifyListeners();
    for (final a in removed) {
      await _secureStorage.delete(key: _passwordKeyFor(a.key));
    }
    await _persist();
    return removed;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _accountsKey,
      _accounts.map((a) => jsonEncode(a.toMetaJson())).toList(),
    );
    for (final a in _accounts) {
      await _secureStorage.write(
          key: _passwordKeyFor(a.key), value: a.password);
    }
    await prefs.setString(_activeKeysKey, jsonEncode(_activeKeyByProfile));
    await prefs.remove(_legacyActiveKeyKey);
  }
}
