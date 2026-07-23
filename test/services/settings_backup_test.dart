import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app_info.dart';
import 'package:iptv_player/data/models/account.dart';
import 'package:iptv_player/data/models/favorite_item.dart';
import 'package:iptv_player/data/models/playback_progress.dart';
import 'package:iptv_player/data/models/watch_history_entry.dart';
import 'package:iptv_player/data/services/accounts_service.dart';
import 'package:iptv_player/data/services/favorites_service.dart';
import 'package:iptv_player/data/services/kids_filter_service.dart';
import 'package:iptv_player/data/services/playback_service.dart';
import 'package:iptv_player/data/services/profiles_service.dart';
import 'package:iptv_player/data/services/settings_backup.dart';
import 'package:iptv_player/data/services/settings_service.dart';
import 'package:iptv_player/data/services/watch_history_service.dart';
import 'package:iptv_player/data/services/watchlist_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/test_support.dart';

void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    mockSecureStorage();
    // Export/import operate on the active profile's playlists + settings.
    ProfilesService.instance.resetForTesting();
    await ProfilesService.instance.load(); // active profile = 'default'
    SettingsService.instance.resetForTesting();
    AccountsService.instance.resetForTesting();
  });

  group('export', () {
    test('includes accounts (with passwords) and appearance', () async {
      await AccountsService.instance.load();
      await AccountsService.instance.addAccount(const Account(
        name: 'Home',
        serverUrl: 'http://host:8080',
        username: 'alice',
        password: 's3cret',
      ));
      await SettingsService.instance.loadFor('default');
      await SettingsService.instance.setThemeMode(ThemeMode.light);
      await SettingsService.instance
          .setThemePreset(kThemePresets.firstWhere((p) => p.id == 'ocean'));
      await SettingsService.instance.setFontChoice(
          kFontChoices.firstWhere((f) => f.id == 'ibm_plex_sans_arabic'));

      final map =
          jsonDecode(await SettingsBackup.export()) as Map<String, dynamic>;

      expect(map['format'], SettingsBackup.formatMarker);
      final account = (map['accounts'] as List).single as Map<String, dynamic>;
      expect(account['serverUrl'], 'http://host:8080');
      expect(account['username'], 'alice');
      expect(account['password'], 's3cret'); // needed for a usable import
      final appearance = map['appearance'] as Map<String, dynamic>;
      expect(appearance['themeMode'], 'light');
      expect(appearance['themePreset'], 'ocean');
      expect(appearance['font'], 'ibm_plex_sans_arabic');
    });

    test('does not carry the PIN or any cache/derived data', () async {
      await AccountsService.instance.load();
      await SettingsService.instance.loadFor('default');
      final json = (await SettingsBackup.export()).toLowerCase();
      // The PIN (a security control) and all cache/derived data stay out.
      // Favorites/history/continue-watching ARE now included (user data), so
      // they're intentionally not asserted absent here.
      expect(json, isNot(contains('pin')));
      expect(json, isNot(contains('lockedcategories')));
      expect(json, isNot(contains('cache')));
    });
  });

  group('import', () {
    test('applies accounts and appearance, reporting counts', () async {
      await AccountsService.instance.load();
      await SettingsService.instance.loadFor('default');

      final doc = jsonEncode({
        'format': SettingsBackup.formatMarker,
        'version': 1,
        'accounts': [
          {
            'name': 'Imported',
            'serverUrl': 'http://srv:80',
            'username': 'bob',
            'password': 'pw',
          },
        ],
        'appearance': {
          'themeMode': 'dark',
          'themePreset': 'ruby',
          'font': 'space_mono',
        },
      });

      final result = await SettingsBackup.import(doc);

      expect(result.accountsImported, 1);
      expect(result.appearanceImported, isTrue);
      expect(AccountsService.instance.accounts.single.username, 'bob');
      expect(AccountsService.instance.accounts.single.password, 'pw');
      expect(SettingsService.instance.themeMode, ThemeMode.dark);
      expect(SettingsService.instance.themePreset.id, 'ruby');
      expect(SettingsService.instance.fontChoice.id, 'space_mono');
    });

    test('round-trips: export then import restores the same state', () async {
      await AccountsService.instance.load();
      await AccountsService.instance.addAccount(const Account(
        name: 'A',
        serverUrl: 'http://a:1',
        username: 'ua',
        password: 'pa',
      ));
      await AccountsService.instance.addAccount(const Account(
        name: 'B',
        serverUrl: 'http://b:2',
        username: 'ub',
        password: 'pb',
      ));
      await SettingsService.instance.loadFor('default');
      await SettingsService.instance.setThemePreset(
          kThemePresets.firstWhere((p) => p.id == 'forest'));

      final exported = await SettingsBackup.export();

      // Wipe and re-import into a clean slate.
      AccountsService.instance.resetForTesting();
      SharedPreferences.setMockInitialValues({});
      mockSecureStorage();
      await AccountsService.instance.load();
      await SettingsService.instance.loadFor('default');
      expect(AccountsService.instance.accounts, isEmpty);

      final result = await SettingsBackup.import(exported);

      expect(result.accountsImported, 2);
      expect(
        AccountsService.instance.accounts.map((a) => a.key).toSet(),
        {'default|http://a:1|ua', 'default|http://b:2|ub'},
      );
      expect(SettingsService.instance.themePreset.id, 'forest');
    });

    test('round-trips favorites, watchlist, watch history, continue-watching',
        () async {
      await AccountsService.instance.load();
      await SettingsService.instance.loadFor('default');
      const account = Account(
        name: 'Home',
        serverUrl: 'http://host:8080',
        username: 'alice',
        password: 's3cret',
      );
      await AccountsService.instance.addAccount(account);

      // One of each kind of per-playlist user data, with fixed timestamps so
      // we can assert they survive the round-trip unchanged.
      await FavoritesService.instance.loadFor(account);
      await FavoritesService.instance
          .toggle(const FavoriteItem(type: 'movie', id: 'm1', name: 'Dune'));
      await WatchlistService.instance.loadFor(account);
      await WatchlistService.instance
          .toggle(const FavoriteItem(type: 'series', id: 's1', name: 'Dark'));
      await WatchHistoryService.instance.loadFor(account);
      await WatchHistoryService.instance.record(WatchHistoryEntry(
        type: 'movie',
        id: 'm1',
        name: 'Dune',
        watchedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      ));
      await PlaybackService.instance.loadFor(account);
      await PlaybackService.instance.save(PlaybackProgress(
        type: 'movie',
        id: 'm1',
        position: const Duration(minutes: 12),
        total: const Duration(minutes: 100),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      ));

      final exported = await SettingsBackup.export();

      // Wipe everything to a clean slate, then import.
      AccountsService.instance.resetForTesting();
      SharedPreferences.setMockInitialValues({});
      mockSecureStorage();
      await AccountsService.instance.load();
      await SettingsService.instance.loadFor('default');
      await SettingsBackup.import(exported);

      final restored = AccountsService.instance.accounts.single;
      final prefs = await SharedPreferences.getInstance();
      // Verify from disk (not stale in-memory) that each set was restored
      // under the imported playlist's key, timestamps/positions intact.
      final favs = prefs.getStringList('favorites_v1_${restored.key}');
      expect(favs, isNotNull);
      expect(favs!.join(), contains('Dune'));
      final watchlist = prefs.getStringList('watchlist_v1_${restored.key}');
      expect(watchlist!.join(), contains('Dark'));
      final hist = prefs.getStringList('watch_history_v1_${restored.key}');
      expect(hist!.join(), contains('"watchedAt":1700000000000'));
      final resume = prefs.getStringList('playback_v1_${restored.key}');
      expect(resume!.join(), contains('"positionMs":720000')); // 12 minutes
    });

    test('round-trips a kids-profile content allowlist', () async {
      await initDbEnvironment(); // KidsFilterService.loadFor reads the catalog
      await AccountsService.instance.load();
      await SettingsService.instance.loadFor('default');
      const account = Account(
        name: 'KidsHome',
        serverUrl: 'http://host:8080',
        username: 'kid',
        password: 'pw',
      );
      await AccountsService.instance.addAccount(account);

      await KidsFilterService.instance.loadFor(account);
      await KidsFilterService.instance.setAllowed('movie', '4', true);
      await KidsFilterService.instance.setAllowed('live', '1', true);

      final exported = await SettingsBackup.export();

      AccountsService.instance.resetForTesting();
      SharedPreferences.setMockInitialValues({});
      mockSecureStorage();
      await KidsFilterService.instance.resetForTesting();
      await AccountsService.instance.load();
      await SettingsService.instance.loadFor('default');
      await SettingsBackup.import(exported);

      final restored = AccountsService.instance.accounts.single;
      await KidsFilterService.instance.loadFor(restored);
      // Assert on the allowlist itself (gate-independent) — enforcement is
      // gated on the active profile's isKids, which this backup test doesn't
      // set up.
      expect(KidsFilterService.instance.isAllowed('movie', '4'), isTrue);
      expect(KidsFilterService.instance.isAllowed('live', '1'), isTrue);
      expect(KidsFilterService.instance.isAllowed('movie', '7'), isFalse);
    });

    test('round-trips an M3U playlist (kind + urls preserved)', () async {
      await AccountsService.instance.load();
      await AccountsService.instance.addAccount(const Account.m3u(
        name: 'My M3U',
        url: 'http://host/list.m3u8',
        epgUrl: 'http://host/epg.xml',
      ));

      final exported = await SettingsBackup.export();

      AccountsService.instance.resetForTesting();
      SharedPreferences.setMockInitialValues({});
      mockSecureStorage();
      await AccountsService.instance.load();

      final result = await SettingsBackup.import(exported);
      expect(result.accountsImported, 1);
      final restored = AccountsService.instance.accounts.single;
      expect(restored.isM3u, isTrue);
      expect(restored.m3uUrl, 'http://host/list.m3u8');
      expect(restored.epgUrl, 'http://host/epg.xml');
    });

    test('skips malformed account entries', () async {
      await AccountsService.instance.load();
      await SettingsService.instance.loadFor('default');
      final doc = jsonEncode({
        'format': SettingsBackup.formatMarker,
        'accounts': [
          {'name': 'no password', 'serverUrl': 'http://x', 'username': 'u'},
          {'serverUrl': 'http://y', 'username': 'u2', 'password': 'p2'},
          'not-a-map',
        ],
      });
      final result = await SettingsBackup.import(doc);
      expect(result.accountsImported, 1);
      expect(AccountsService.instance.accounts.single.username, 'u2');
    });

    test('skips wrong-typed account fields instead of throwing', () async {
      await AccountsService.instance.load();
      await SettingsService.instance.loadFor('default');
      // A well-labeled file whose fields have the wrong types (e.g. a number
      // or an object where a string is expected) must not abort the import or
      // half-apply - the bad entries are skipped like missing ones.
      final doc = jsonEncode({
        'format': SettingsBackup.formatMarker,
        'accounts': [
          {'serverUrl': 8080, 'username': 'x', 'password': 'p'}, // num url
          {'serverUrl': 'http://ok', 'username': {'nested': true}, 'password': 'p'},
          {'serverUrl': 'http://good', 'username': 'u', 'password': 'p'},
        ],
        'appearance': {'themeMode': 'light'},
      });

      final result = await SettingsBackup.import(doc);

      expect(result.accountsImported, 1);
      expect(AccountsService.instance.accounts.single.serverUrl, 'http://good');
      expect(result.appearanceImported, isTrue);
    });

    test('tolerates a file with only appearance', () async {
      await AccountsService.instance.load();
      await SettingsService.instance.loadFor('default');
      final doc = jsonEncode({
        'format': SettingsBackup.formatMarker,
        'appearance': {'themeMode': 'light'},
      });
      final result = await SettingsBackup.import(doc);
      expect(result.accountsImported, 0);
      expect(result.appearanceImported, isTrue);
      expect(SettingsService.instance.themeMode, ThemeMode.light);
    });

    test('rejects non-JSON input', () async {
      expect(
        () => SettingsBackup.import('this is not json'),
        throwsA(isA<SettingsBackupException>()),
      );
    });

    test('rejects JSON without the format marker', () async {
      final doc = jsonEncode({'accounts': [], 'appearance': {}});
      expect(
        () => SettingsBackup.import(doc),
        throwsA(isA<SettingsBackupException>()),
      );
    });

    test('the wrong-format error is worded with the app name', () async {
      // The message tracks appName rather than a hardcoded string, so a
      // rename flows through to error text too.
      final doc = jsonEncode({'not': 'ours'});
      expect(
        () => SettingsBackup.import(doc),
        throwsA(isA<SettingsBackupException>()
            .having((e) => e.message, 'message', contains(appName))),
      );
    });
  });
}
