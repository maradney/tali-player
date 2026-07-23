import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../db/catalog_database.dart';
import '../models/account.dart';

/// One-time upgrade migration that folds a pre-profiles install into the new
/// profiles model. Before profiles existed, an account's key (and therefore
/// every storage key derived from it) was `serverUrl|username`; now it's
/// `profileId|serverUrl|username`. This walks the existing playlists and
/// re-keys all of their local data into the starter profile's scope
/// ([Account.defaultProfileId]) so nothing is orphaned, and moves the old
/// global appearance settings into that profile too.
///
/// Idempotent: guarded by a done-flag and a no-op when there are no legacy
/// (unprefixed) accounts, so it's safe to call unconditionally at every
/// startup. Runs BEFORE ProfilesService/AccountsService/SettingsService load.
class ProfilesMigration {
  ProfilesMigration._();

  static const _doneFlagKey = 'profiles_migration_v1_done';

  /// Per-account SharedPreferences base keys (value is `${base}_$accountKey`).
  /// Mirrors the `_prefsKeyFor` conventions in the per-account services plus
  /// the search screen's recent-searches key.
  static const _perAccountBaseKeys = <String>[
    'favorites_v1',
    'playback_v1',
    'watch_history_v1',
    'pin_lock_v1',
    'channel_prefs_v1',
    'recent_searches_v1',
  ];

  /// Global (unprefixed) settings keys moved into the default profile's scope.
  static const _settingsBaseKeys = <String>[
    'settings_theme_mode',
    'settings_theme_preset',
    'settings_font',
    'settings_grid_density',
    'settings_language',
  ];

  static String _passwordKeyFor(String accountKey) =>
      'account_password_$accountKey';

  static Future<void> runIfNeeded({
    FlutterSecureStorage secureStorage = const FlutterSecureStorage(),
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_doneFlagKey) ?? false) return;

    final rawAccounts = prefs.getStringList('accounts_v1') ?? [];
    // Legacy entries are the ones without a profileId. If every entry already
    // has one (or there are none), there's nothing to move — just flag done.
    final metas = <Map<String, dynamic>>[];
    var hasLegacy = false;
    for (final s in rawAccounts) {
      try {
        final m = jsonDecode(s) as Map<String, dynamic>;
        if (m['profileId'] == null) hasLegacy = true;
        metas.add(m);
      } catch (_) {
        // keep unparseable entries as-is (skip them in the rewrite below)
      }
    }

    if (!hasLegacy) {
      await prefs.setBool(_doneFlagKey, true);
      return;
    }

    const profileId = Account.defaultProfileId;
    final rewritten = <String>[];
    String? migratedActiveKey;
    final legacyActive = prefs.getString('active_account_key_v1');

    for (final meta in metas) {
      if (meta['profileId'] != null) {
        rewritten.add(jsonEncode(meta));
        continue;
      }
      final serverUrl = meta['serverUrl'] as String?;
      final username = meta['username'] as String?;
      if (serverUrl == null || username == null) continue; // drop the corrupt

      final oldKey = '$serverUrl|$username';
      final newKey = '$profileId|$serverUrl|$username';

      await _movePerAccountData(prefs, oldKey, newKey);
      await CatalogDatabase.instance.reassignAccountKey(oldKey, newKey);

      // Password: inline-password entries are left for AccountsService to
      // migrate under the new key; otherwise move the secure-storage entry.
      if (meta['password'] == null) {
        final pw = await secureStorage.read(key: _passwordKeyFor(oldKey));
        if (pw != null) {
          await secureStorage.write(key: _passwordKeyFor(newKey), value: pw);
          await secureStorage.delete(key: _passwordKeyFor(oldKey));
        }
      }

      meta['profileId'] = profileId;
      rewritten.add(jsonEncode(meta));
      if (legacyActive == oldKey) migratedActiveKey = newKey;
    }

    await prefs.setStringList('accounts_v1', rewritten);

    // Single legacy active key → per-profile active-key map.
    if (migratedActiveKey != null) {
      await prefs.setString(
        'active_account_keys_v1',
        jsonEncode({profileId: migratedActiveKey}),
      );
    }
    await prefs.remove('active_account_key_v1');

    // Global appearance settings → the default profile's scope.
    for (final base in _settingsBaseKeys) {
      final v = prefs.getString(base);
      if (v != null) {
        await prefs.setString('${base}_$profileId', v);
        await prefs.remove(base);
      }
    }

    await prefs.setBool(_doneFlagKey, true);
  }

  /// Moves every per-account SharedPreferences value from [oldKey]'s scope to
  /// [newKey]'s, preserving each value's stored type (string vs string-list).
  static Future<void> _movePerAccountData(
    SharedPreferences prefs,
    String oldKey,
    String newKey,
  ) async {
    for (final base in _perAccountBaseKeys) {
      final from = '${base}_$oldKey';
      final to = '${base}_$newKey';
      final value = prefs.get(from);
      if (value == null) continue;
      if (value is List) {
        await prefs.setStringList(to, value.cast<String>());
      } else if (value is String) {
        await prefs.setString(to, value);
      } else if (value is bool) {
        await prefs.setBool(to, value);
      } else if (value is int) {
        await prefs.setInt(to, value);
      } else if (value is double) {
        await prefs.setDouble(to, value);
      }
      await prefs.remove(from);
    }
  }
}
