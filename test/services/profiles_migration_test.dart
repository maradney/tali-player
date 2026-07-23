import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/services/profiles_migration.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/test_support.dart';

void main() {
  late Map<String, String> secureStore;

  const server = 'http://host:8080';
  const user = 'alice';
  const oldKey = '$server|$user';
  const newKey = 'default|$server|$user';

  setUp(() async {
    await initDbEnvironment(); // reassignAccountKey opens the catalog db
    secureStore = mockSecureStorage();
  });

  void seedLegacyInstall() {
    SharedPreferences.setMockInitialValues({
      'accounts_v1': [
        jsonEncode({'name': 'My List', 'serverUrl': server, 'username': user}),
      ],
      'active_account_key_v1': oldKey,
      // Per-account data under the pre-profiles (unprefixed) key.
      'favorites_v1_$oldKey': ['live:1', 'movie:2'],
      'watch_history_v1_$oldKey': ['h1'],
      'pin_lock_v1_$oldKey': '{"pinHash":"abc","pinSalt":"de"}',
      'recent_searches_v1_$oldKey': ['batman'],
      // Old global appearance settings.
      'settings_theme_mode': 'light',
      'settings_language': 'arabic',
    });
    secureStore['account_password_$oldKey'] = 'pw';
  }

  test('re-keys accounts, data, password, settings, and active key', () async {
    seedLegacyInstall();

    await ProfilesMigration.runIfNeeded();

    final prefs = await SharedPreferences.getInstance();

    // Account meta now carries the default profile id.
    final meta = jsonDecode(prefs.getStringList('accounts_v1')!.single)
        as Map<String, dynamic>;
    expect(meta['profileId'], 'default');

    // Per-account data moved to the prefixed key; old key gone.
    expect(prefs.getStringList('favorites_v1_$newKey'), ['live:1', 'movie:2']);
    expect(prefs.getStringList('favorites_v1_$oldKey'), isNull);
    expect(prefs.getStringList('watch_history_v1_$newKey'), ['h1']);
    expect(prefs.getString('pin_lock_v1_$newKey'), contains('pinHash'));
    expect(prefs.getStringList('recent_searches_v1_$newKey'), ['batman']);

    // Password moved in secure storage.
    expect(secureStore['account_password_$newKey'], 'pw');
    expect(secureStore.containsKey('account_password_$oldKey'), isFalse);

    // Global settings moved into the default profile's scope.
    expect(prefs.getString('settings_theme_mode_default'), 'light');
    expect(prefs.getString('settings_theme_mode'), isNull);
    expect(prefs.getString('settings_language_default'), 'arabic');

    // Active playlist key migrated into the per-profile map.
    final activeMap = jsonDecode(prefs.getString('active_account_keys_v1')!)
        as Map<String, dynamic>;
    expect(activeMap, {'default': newKey});
    expect(prefs.getString('active_account_key_v1'), isNull);
  });

  test('is idempotent — a second run changes nothing', () async {
    seedLegacyInstall();
    await ProfilesMigration.runIfNeeded();
    final prefs = await SharedPreferences.getInstance();
    final after1 = prefs.getStringList('accounts_v1');

    await ProfilesMigration.runIfNeeded();
    expect(prefs.getStringList('accounts_v1'), after1);
    // Still exactly one favorites entry (not moved twice / duplicated).
    expect(prefs.getStringList('favorites_v1_$newKey'), ['live:1', 'movie:2']);
  });

  test('no-op when accounts already carry a profileId', () async {
    SharedPreferences.setMockInitialValues({
      'accounts_v1': [
        jsonEncode({
          'profileId': 'default',
          'name': 'My List',
          'serverUrl': server,
          'username': user,
        }),
      ],
      'favorites_v1_$newKey': ['live:1'],
    });

    await ProfilesMigration.runIfNeeded();

    final prefs = await SharedPreferences.getInstance();
    // Untouched.
    expect(prefs.getStringList('favorites_v1_$newKey'), ['live:1']);
    expect(prefs.getBool('profiles_migration_v1_done'), isTrue);
  });

  test('no-op on a fresh install (no accounts at all)', () async {
    SharedPreferences.setMockInitialValues({});
    await ProfilesMigration.runIfNeeded();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('profiles_migration_v1_done'), isTrue);
    expect(prefs.getStringList('accounts_v1'), isNull);
  });
}
