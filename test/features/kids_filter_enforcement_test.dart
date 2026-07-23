import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/models/favorite_item.dart';
import 'package:iptv_player/data/services/favorites_service.dart';
import 'package:iptv_player/data/services/kids_filter_service.dart';
import 'package:iptv_player/data/services/profiles_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/test_support.dart';

/// Integration proof that the enforcement path the discovery surfaces use —
/// real snapshot items from a per-account service, filtered by the real
/// [KidsFilterService] predicate, gated on the active profile — actually drops
/// a blocked item. Every discovery screen applies exactly this
/// `!isHiddenForItem(...)` filter over its item list, so a break here mirrors a
/// break there. Kept hermetic (no widget tree) so it can't hang on pumped
/// timers/animations the way a full-screen test can.
void main() {
  setUp(() async {
    await initDbEnvironment();
    SharedPreferences.setMockInitialValues({});
    ProfilesService.instance.resetForTesting();
    await KidsFilterService.instance.resetForTesting();
  });

  tearDown(() async {
    ProfilesService.instance.resetForTesting();
    await KidsFilterService.instance.resetForTesting();
  });

  /// The filter every discovery surface applies over its item list.
  List<String> visibleNames(Iterable<FavoriteItem> items) => items
      .where((i) => !KidsFilterService.instance
          .isHiddenForItem(i.type, i.id, categoryId: i.categoryId))
      .map((i) => i.name)
      .toList();

  test('a kids profile hides a favorite whose category is not allowed',
      () async {
    await ProfilesService.instance.load();
    await ProfilesService.instance.addProfile(name: 'Kids', isKids: true);

    final account = accountNamed('kids-enforcement');
    await FavoritesService.instance.loadFor(account);
    await FavoritesService.instance.toggle(const FavoriteItem(
        type: 'movie', id: 'ok', name: 'Paddington', categoryId: '4'));
    await FavoritesService.instance.toggle(const FavoriteItem(
        type: 'movie', id: 'bad', name: 'Slasher', categoryId: '7'));

    await KidsFilterService.instance.loadFor(account);
    await KidsFilterService.instance.setAllowed('movie', '4', true);

    // Only the allowed-category favorite survives the filter.
    expect(visibleNames(FavoritesService.instance.items), ['Paddington']);
  });

  test('the same favorites are all visible in a normal profile', () async {
    await ProfilesService.instance.load(); // active = 'default' (not kids)

    final account = accountNamed('normal-enforcement');
    await FavoritesService.instance.loadFor(account);
    await FavoritesService.instance.toggle(const FavoriteItem(
        type: 'movie', id: 'ok', name: 'Paddington', categoryId: '4'));
    await FavoritesService.instance.toggle(const FavoriteItem(
        type: 'movie', id: 'bad', name: 'Slasher', categoryId: '7'));

    await KidsFilterService.instance.loadFor(account);
    // No kids profile active -> the filter is inert, nothing is hidden.
    expect(visibleNames(FavoritesService.instance.items),
        containsAll(['Paddington', 'Slasher']));
  });
}
