import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/db/catalog_database.dart';
import 'package:iptv_player/data/models/catalog_row.dart';
import 'package:iptv_player/data/models/search_result.dart' show ContentType;
import 'package:iptv_player/data/services/kids_filter_service.dart';
import 'package:iptv_player/data/services/profiles_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/test_support.dart';

void main() {
  final service = KidsFilterService.instance;

  setUpAll(() async {
    await initDbEnvironment();
  });

  // Enforcement follows the ACTIVE profile's isKids flag, so each test starts
  // with a kids profile active. `_makeNormalProfileActive` flips to a normal
  // one to prove the filter goes inert.
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ProfilesService.instance.resetForTesting();
    await service.resetForTesting();
    await ProfilesService.instance.load(); // seeds 'default' (normal)
    // Add + activate a kids profile.
    await ProfilesService.instance.addProfile(name: 'Kids', isKids: true);
  });

  Future<void> makeNormalProfileActive() =>
      ProfilesService.instance.switchTo(ProfilesService.defaultProfileId);

  test('a kids profile with an empty allowlist hides everything (default-deny)',
      () async {
    await service.loadFor(accountNamed('kf-empty'));
    expect(service.isRestricting, isTrue);
    // Nothing allowed yet -> every category is hidden. Safe by default.
    expect(service.isCategoryHidden('movie', '4'), isTrue);
    expect(service.isCategoryHidden('live', '1'), isTrue);
    expect(service.isHiddenForItem('movie', '120', categoryId: '4'), isTrue);
  });

  test('a normal profile is never restricted, whatever is stored', () async {
    final account = accountNamed('kf-normal');
    await service.loadFor(account);
    await service.setAllowed('movie', '4', true); // config exists...
    await makeNormalProfileActive(); // ...but the active profile isn't kids
    expect(service.isRestricting, isFalse);
    expect(service.isCategoryHidden('movie', '7'), isFalse);
    expect(service.isHiddenForItem('movie', '120', categoryId: '7'), isFalse);
    expect(service.allowedCategoryKeysOrNull, isNull);
  });

  test('allowlist reveals only allowed categories', () async {
    await service.loadFor(accountNamed('kf-allow'));
    await service.setAllowed('movie', '4', true);
    await service.setAllowed('live', '1', true);

    expect(service.isCategoryHidden('movie', '4'), isFalse);
    expect(service.isCategoryHidden('live', '1'), isFalse);
    expect(service.isCategoryHidden('movie', '7'), isTrue);
    expect(service.isCategoryHidden('series', '4'), isTrue); // type matters
    expect(service.isCategoryHidden('live', '2'), isTrue);
  });

  test('isHiddenForItem uses the passed-in category', () async {
    await service.loadFor(accountNamed('kf-item-hint'));
    await service.setAllowed('movie', '4', true);
    expect(service.isHiddenForItem('movie', '55', categoryId: '4'), isFalse);
    expect(service.isHiddenForItem('movie', '55', categoryId: '7'), isTrue);
  });

  test('isHiddenForItem resolves category from the catalog index', () async {
    final account = accountNamed('kf-index');
    await CatalogDatabase.instance.replaceTypeItems(
      account.key,
      ContentType.live,
      [
        CatalogRow(
          accountKey: account.key,
          type: ContentType.live,
          id: '77',
          name: 'Allowed Channel',
          categoryId: '1',
        ),
        CatalogRow(
          accountKey: account.key,
          type: ContentType.live,
          id: '88',
          name: 'Blocked Channel',
          categoryId: '2',
        ),
      ],
    );
    await service.loadFor(account); // pulls the index
    await service.setAllowed('live', '1', true);

    expect(service.isHiddenForItem('live', '77'), isFalse);
    expect(service.isHiddenForItem('live', '88'), isTrue);
  });

  test('an unresolvable item is hidden under default-deny', () async {
    await service.loadFor(accountNamed('kf-unresolvable'));
    await service.setAllowed('movie', '4', true);
    // No hint and not in the index -> better to hide than to leak.
    expect(service.isHiddenForItem('movie', 'ghost'), isTrue);
  });

  test('isAllowed reflects the allowlist for the curation UI', () async {
    await service.loadFor(accountNamed('kf-isallowed'));
    await service.setAllowed('movie', '4', true);
    expect(service.isAllowed('movie', '4'), isTrue);
    expect(service.isAllowed('movie', '5'), isFalse);
  });

  test('allowlist persists to shared_preferences and reloads', () async {
    final account = accountNamed('kf-persist');
    await service.loadFor(account);
    await service.setAllowed('series', '2', true);

    final prefs = await SharedPreferences.getInstance();
    final map = jsonDecode(prefs.getString('kids_filter_v1_${account.key}')!)
        as Map<String, dynamic>;
    expect(map['allowed'], contains('series:2'));

    await service.resetForTesting();
    await service.loadFor(account);
    expect(service.isCategoryHidden('series', '2'), isFalse);
    expect(service.isCategoryHidden('series', '9'), isTrue);
  });

  test('exportFor/importFor round-trips the allowlist for backup', () async {
    final source = accountNamed('kf-export');
    await service.loadFor(source);
    await service.setAllowed('movie', '4', true);
    await service.setAllowed('live', '1', true);

    final exported = await service.exportFor(source);
    expect(exported, isNotNull);

    final target = accountNamed('kf-import');
    await service.importFor(target, exported!);
    await service.resetForTesting();
    await service.loadFor(target);
    expect(service.isCategoryHidden('movie', '4'), isFalse);
    expect(service.isCategoryHidden('movie', '7'), isTrue);
  });

  test('exportFor returns null when nothing is stored', () async {
    final exported = await service.exportFor(accountNamed('kf-none'));
    expect(exported, isNull);
  });

  test('deleteFor wipes the persisted allowlist', () async {
    final account = accountNamed('kf-delete');
    await service.loadFor(account);
    await service.setAllowed('movie', '4', true);
    await service.deleteFor(account);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('kids_filter_v1_${account.key}'), isNull);
  });
}
