import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/models/account.dart';
import 'package:iptv_player/data/services/accounts_service.dart';
import 'package:iptv_player/data/services/profiles_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/test_support.dart';

void main() {
  final service = AccountsService.instance;
  late Map<String, String> secureStore;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    secureStore = mockSecureStorage();
    // Establish an active profile ('default'); test accounts default to it,
    // so AccountsService's profile-scoped getters see them.
    ProfilesService.instance.resetForTesting();
    await ProfilesService.instance.load();
    service.resetForTesting();
  });

  test('loads empty when nothing is saved', () async {
    await service.load();
    expect(service.accounts, isEmpty);
    expect(service.activeAccount, isNull);
  });

  test('addAccount stores metadata in prefs and password in secure storage',
      () async {
    await service.load();
    final account = accountNamed('acc-add');
    await service.addAccount(account);

    expect(service.activeAccount?.key, account.key);

    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList('accounts_v1')!;
    final meta = jsonDecode(rawList.single) as Map<String, dynamic>;
    expect(meta['username'], 'acc-add');
    expect(meta.containsKey('password'), isFalse); // never in plaintext prefs

    expect(secureStore['account_password_${account.key}'], account.password);
  });

  test('addAccount replaces an existing account with the same key', () async {
    await service.load();
    const first = Account(
      name: 'Old name',
      serverUrl: 'http://host:8080',
      username: 'dupe',
      password: 'old',
    );
    const updated = Account(
      name: 'New name',
      serverUrl: 'http://host:8080',
      username: 'dupe',
      password: 'new',
    );
    await service.addAccount(first);
    await service.addAccount(updated);

    expect(service.accounts, hasLength(1));
    expect(service.accounts.single.name, 'New name');
    expect(service.accounts.single.password, 'new');
  });

  test('switchTo changes the active account only for a known key', () async {
    await service.load();
    final a = accountNamed('acc-a');
    final b = accountNamed('acc-b');
    await service.addAccount(a);
    await service.addAccount(b); // b becomes active

    await service.switchTo(a.key);
    expect(service.activeAccount?.key, a.key);

    await service.switchTo('unknown|key');
    expect(service.activeAccount?.key, a.key); // unchanged
  });

  test('removeAccount deletes password and reassigns active', () async {
    await service.load();
    final a = accountNamed('acc-rm-a');
    final b = accountNamed('acc-rm-b');
    await service.addAccount(a);
    await service.addAccount(b); // active = b

    await service.removeAccount(b.key);
    expect(service.accounts.map((x) => x.key), [a.key]);
    expect(service.activeAccount?.key, a.key); // fell back to remaining
    expect(secureStore.containsKey('account_password_${b.key}'), isFalse);
  });

  test('removing the last account clears the active key', () async {
    await service.load();
    final a = accountNamed('acc-only');
    await service.addAccount(a);
    await service.removeAccount(a.key);
    expect(service.accounts, isEmpty);
    expect(service.activeAccount, isNull);
  });

  test('migrates a legacy inline-password account into secure storage',
      () async {
    final account = accountNamed('acc-legacy');
    // Legacy shape: password stored inline in the metadata JSON.
    SharedPreferences.setMockInitialValues({
      'accounts_v1': [
        jsonEncode({
          'name': account.name,
          'serverUrl': account.serverUrl,
          'username': account.username,
          'password': 'legacy-pw',
        }),
      ],
      'active_account_key_v1': account.key,
    });
    secureStore = mockSecureStorage();
    service.resetForTesting();

    await service.load();

    expect(service.accounts.single.password, 'legacy-pw');
    expect(service.activeAccount?.key, account.key);
    // Migrated into secure storage...
    expect(secureStore['account_password_${account.key}'], 'legacy-pw');
    // ...and rewritten out of the plaintext prefs blob.
    final prefs = await SharedPreferences.getInstance();
    final meta =
        jsonDecode(prefs.getStringList('accounts_v1')!.single) as Map<String, dynamic>;
    expect(meta.containsKey('password'), isFalse);
  });

  test('accounts and activeAccount are scoped to the active profile', () async {
    await service.load();
    final profiles = ProfilesService.instance;
    final kids = await profiles.addProfile(name: 'Kids'); // now active

    // A playlist added under Kids (login stamps the active profile id).
    final kidsAcc = Account(
      profileId: kids.id,
      name: 'kids-list',
      serverUrl: 'http://host:8080',
      username: 'kid',
      password: 'pw',
    );
    await service.addAccount(kidsAcc);

    // Under Kids we see only its playlist.
    expect(service.accounts.map((a) => a.key), [kidsAcc.key]);
    expect(service.activeAccount?.key, kidsAcc.key);

    // Add a default-profile playlist while Kids is active — still hidden.
    await profiles.switchTo(ProfilesService.defaultProfileId);
    final def = accountNamed('def-list');
    await service.addAccount(def);
    expect(service.accounts.map((a) => a.key), [def.key]);
    expect(service.activeAccount?.key, def.key);

    // Switching back to Kids restores its playlist + active selection.
    await profiles.switchTo(kids.id);
    expect(service.accounts.map((a) => a.key), [kidsAcc.key]);
    expect(service.activeAccount?.key, kidsAcc.key);
  });

  test('removeAccountsForProfile returns and clears only that profile\'s '
      'playlists', () async {
    await service.load();
    final profiles = ProfilesService.instance;
    final kids = await profiles.addProfile(name: 'Kids');
    final kidsAcc = Account(
      profileId: kids.id,
      name: 'k',
      serverUrl: 'http://host:8080',
      username: 'k',
      password: 'pw',
    );
    await service.addAccount(kidsAcc);
    await profiles.switchTo(ProfilesService.defaultProfileId);
    final def = accountNamed('keep-me');
    await service.addAccount(def);

    final removed = await service.removeAccountsForProfile(kids.id);
    expect(removed.map((a) => a.key), [kidsAcc.key]);
    // The default profile's playlist is untouched.
    expect(service.allAccounts.map((a) => a.key), [def.key]);
    expect(secureStore.containsKey('account_password_${kidsAcc.key}'), isFalse);
    expect(secureStore['account_password_${def.key}'], def.password);
  });

  test('drops a metadata entry that has no recoverable password', () async {
    final account = accountNamed('acc-nopw');
    SharedPreferences.setMockInitialValues({
      'accounts_v1': [
        jsonEncode({
          'name': account.name,
          'serverUrl': account.serverUrl,
          'username': account.username,
        }),
      ],
    });
    secureStore = mockSecureStorage(); // empty - no stored password
    service.resetForTesting();

    await service.load();
    expect(service.accounts, isEmpty);
  });
}
