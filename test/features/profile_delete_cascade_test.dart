import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/db/catalog_database.dart';
import 'package:iptv_player/data/models/account.dart';
import 'package:iptv_player/data/models/catalog_row.dart';
import 'package:iptv_player/data/models/favorite_item.dart';
import 'package:iptv_player/data/models/search_result.dart';
import 'package:iptv_player/data/services/accounts_service.dart';
import 'package:iptv_player/data/services/favorites_service.dart';
import 'package:iptv_player/data/services/kids_filter_service.dart';
import 'package:iptv_player/data/services/profiles_service.dart';
import 'package:iptv_player/data/services/settings_service.dart';
import 'package:iptv_player/features/profiles/profile_switching.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/test_support.dart';

/// Guards the core promise of the feature: deleting a profile removes ONLY its
/// playlists and data, leaving every other profile untouched.
void main() {
  late Account defAccount;
  late Account kidsAccount;
  late String kidsId;

  setUp(() async {
    await initDbEnvironment();
    SharedPreferences.setMockInitialValues({});
    mockSecureStorage();
    ProfilesService.instance.resetForTesting();
    AccountsService.instance.resetForTesting();
    SettingsService.instance.resetForTesting();

    await ProfilesService.instance.load(); // active = 'default'
    await AccountsService.instance.load();

    // A playlist + favorite + cached catalog in the default profile.
    defAccount = accountNamed('keep');
    await AccountsService.instance.addAccount(defAccount);
    await FavoritesService.instance.loadFor(defAccount);
    await FavoritesService.instance
        .toggle(const FavoriteItem(type: 'movie', id: 'd1', name: 'Keeper'));
    await CatalogDatabase.instance.replaceTypeItems(
      defAccount.key,
      ContentType.movie,
      [
        CatalogRow(
          accountKey: defAccount.key,
          type: ContentType.movie,
          id: 'd1',
          name: 'Keeper',
          categoryId: '1',
        ),
      ],
    );

    // A second profile with its own playlist + favorite + cached catalog.
    final kids = await ProfilesService.instance.addProfile(name: 'Kids');
    kidsId = kids.id;
    kidsAccount = Account(
      profileId: kidsId,
      name: 'kids',
      serverUrl: 'http://host:8080',
      username: 'kid',
      password: 'pw',
    );
    await AccountsService.instance.addAccount(kidsAccount);
    await FavoritesService.instance.loadFor(kidsAccount);
    await FavoritesService.instance
        .toggle(const FavoriteItem(type: 'movie', id: 'k1', name: 'Cartoon'));
    await CatalogDatabase.instance.replaceTypeItems(
      kidsAccount.key,
      ContentType.movie,
      [
        CatalogRow(
          accountKey: kidsAccount.key,
          type: ContentType.movie,
          id: 'k1',
          name: 'Cartoon',
          categoryId: '1',
        ),
      ],
    );
    // A content allowlist on the kids profile's playlist.
    await KidsFilterService.instance.loadFor(kidsAccount);
    await KidsFilterService.instance.setAllowed('movie', '1', true);

    await SettingsService.instance.loadFor(kidsId);
  });

  test('deleting a profile wipes its data and leaves others intact', () async {
    await deleteProfileWithData(kidsId);

    // The profile is gone; default remains active.
    expect(ProfilesService.instance.profiles.map((p) => p.id),
        isNot(contains(kidsId)));

    // Kids' playlist, favorites, and catalog are gone.
    expect(AccountsService.instance.allAccounts.map((a) => a.key),
        isNot(contains(kidsAccount.key)));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('favorites_v1_${kidsAccount.key}'), isNull);
    expect(prefs.getString('kids_filter_v1_${kidsAccount.key}'), isNull);
    expect(await CatalogDatabase.instance.countFor(kidsAccount.key), 0);

    // The default profile's playlist, favorites, and catalog are untouched.
    expect(AccountsService.instance.allAccounts.map((a) => a.key),
        contains(defAccount.key));
    expect(prefs.getStringList('favorites_v1_${defAccount.key}'), isNotNull);
    expect(await CatalogDatabase.instance.countFor(defAccount.key), 1);
  });
}
