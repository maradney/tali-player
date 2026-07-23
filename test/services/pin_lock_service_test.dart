import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/db/catalog_database.dart';
import 'package:iptv_player/data/models/catalog_row.dart';
import 'package:iptv_player/data/models/search_result.dart';
import 'package:iptv_player/data/services/pin_lock_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/test_support.dart';

void main() {
  final service = PinLockService.instance;

  setUpAll(() async {
    await initDbEnvironment();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('PIN management', () {
    test('no PIN by default; setPin makes hasPin true', () async {
      final account = accountNamed('pin-set');
      await service.loadFor(account);
      expect(service.hasPin, isFalse);
      await service.setPin('1234');
      expect(service.hasPin, isTrue);
    });

    test('verifyPin only accepts the exact PIN', () async {
      await service.loadFor(accountNamed('pin-verify'));
      await service.setPin('4321');
      expect(service.verifyPin('4321'), isTrue);
      expect(service.verifyPin('0000'), isFalse);
      expect(service.verifyPin(''), isFalse);
    });

    test('clearPin removes the PIN and all locks', () async {
      await service.loadFor(accountNamed('pin-clear'));
      await service.setPin('1234');
      await service.setCategoryLocked('live', '9', true);
      await service.setItemLocked('movie', '120', true);

      await service.clearPin();
      expect(service.hasPin, isFalse);
      expect(service.isCategoryLocked('live', '9'), isFalse);
      expect(service.isItemLocked('movie', '120'), isFalse);
    });
  });

  group('lock state', () {
    test('category and item locks toggle independently', () async {
      await service.loadFor(accountNamed('pin-toggle'));
      await service.setCategoryLocked('live', '9', true);
      expect(service.isCategoryLocked('live', '9'), isTrue);
      expect(service.isCategoryLocked('live', '8'), isFalse);

      await service.setItemLocked('movie', '120', true);
      expect(service.isItemLocked('movie', '120'), isTrue);

      await service.setCategoryLocked('live', '9', false);
      expect(service.isCategoryLocked('live', '9'), isFalse);
      expect(service.isItemLocked('movie', '120'), isTrue); // unaffected
    });

    test('isLocked is true for a locked item', () async {
      await service.loadFor(accountNamed('pin-locked-item'));
      await service.setItemLocked('movie', '120', true);
      expect(service.isLocked('movie', '120'), isTrue);
    });

    test('isLocked uses a passed-in categoryId', () async {
      await service.loadFor(accountNamed('pin-locked-cat-param'));
      await service.setCategoryLocked('live', '9', true);
      expect(service.isLocked('live', '77', categoryId: '9'), isTrue);
      expect(service.isLocked('live', '77', categoryId: '8'), isFalse);
      expect(service.isLocked('live', '77'), isFalse); // no hint, not in index
    });

    test('isCategoryLockedForItem sees only the category lock, not item locks',
        () async {
      // Backs the discovery-surface rule: category-locked titles are hidden
      // wholesale, while individually-locked items stay visible (gated on open).
      await service.loadFor(accountNamed('pin-cat-for-item'));
      await service.setCategoryLocked('movie', '4', true);
      await service.setItemLocked('movie', '120', true);

      // In the locked category -> reported as category-locked.
      expect(
          service.isCategoryLockedForItem('movie', '55', categoryId: '4'), isTrue);
      // Item-locked but NOT in a locked category -> NOT category-locked, so it
      // should still be shown (and gated on open by isLocked).
      expect(service.isCategoryLockedForItem('movie', '120', categoryId: '7'),
          isFalse);
      expect(service.isLocked('movie', '120', categoryId: '7'), isTrue);
      // Unlocking the category clears it.
      await service.setCategoryLocked('movie', '4', false);
      expect(service.isCategoryLockedForItem('movie', '55', categoryId: '4'),
          isFalse);
    });

    test('lockedCategoryKeys exposes the locked-category set (unmodifiable)',
        () async {
      await service.loadFor(accountNamed('pin-cat-keys'));
      await service.setCategoryLocked('movie', '4', true);
      await service.setCategoryLocked('series', '5', true);
      expect(service.lockedCategoryKeys, {'movie:4', 'series:5'});
      expect(() => service.lockedCategoryKeys.add('live:9'),
          throwsUnsupportedError);
    });

    test('isLocked falls back to the catalog index when no categoryId given',
        () async {
      // This is the regression the category-lock fix addressed: a favorite
      // reached without a stored categoryId still gets blocked because the
      // service resolves its category from the search catalog.
      final account = accountNamed('pin-index-fallback');
      await CatalogDatabase.instance.replaceTypeItems(
        account.key,
        ContentType.live,
        [
          CatalogRow(
            accountKey: account.key,
            type: ContentType.live,
            id: '77',
            name: 'Some Channel',
            categoryId: '9',
          ),
        ],
      );
      await service.loadFor(account); // pulls the category index
      await service.setCategoryLocked('live', '9', true);

      // No categoryId passed - resolved from the index (live:77 -> 9).
      expect(service.isLocked('live', '77'), isTrue);
      // An item not in the index and not itself locked stays open.
      expect(service.isLocked('live', '404'), isFalse);
    });
  });

  group('persistence', () {
    test('locks and PIN survive to shared_preferences, PIN never in plaintext',
        () async {
      final account = accountNamed('pin-persist');
      await service.loadFor(account);
      await service.setPin('1234');
      await service.setCategoryLocked('series', '2', true);
      await service.setItemLocked('movie', '120', true);

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('pin_lock_v1_${account.key}')!;
      // Only a salted hash lands on disk - never the PIN itself.
      expect(raw, isNot(contains('1234')));
      final map = jsonDecode(raw) as Map<String, dynamic>;
      expect(map['pinHash'], isA<String>());
      expect((map['pinHash'] as String), isNotEmpty);
      expect((map['pinSalt'] as String), isNotEmpty);
      expect(map['lockedCategories'], contains('series:2'));
      expect(map['lockedItems'], contains('movie:120'));
    });

    test('same PIN hashes differently per salt (no rainbow-table lookups)',
        () async {
      await service.loadFor(accountNamed('pin-salt-a'));
      await service.setPin('1234');
      final prefsA = await SharedPreferences.getInstance();
      final hashA = (jsonDecode(prefsA.getString(
              'pin_lock_v1_${accountNamed('pin-salt-a').key}')!)
          as Map<String, dynamic>)['pinHash'];

      await service.loadFor(accountNamed('pin-salt-b'));
      await service.setPin('1234');
      final prefsB = await SharedPreferences.getInstance();
      final hashB = (jsonDecode(prefsB.getString(
              'pin_lock_v1_${accountNamed('pin-salt-b').key}')!)
          as Map<String, dynamic>)['pinHash'];

      expect(hashA, isNot(hashB));
    });

    test('migrates a legacy plaintext PIN to a hash on first load', () async {
      final account = accountNamed('pin-legacy');
      SharedPreferences.setMockInitialValues({
        'pin_lock_v1_${account.key}': jsonEncode({
          'pin': '9876', // pre-hashing format
          'lockedCategories': ['live:9'],
          'lockedItems': <String>[],
        }),
      });
      await service.loadFor(account);

      // Still verifies with the same PIN, locks intact...
      expect(service.verifyPin('9876'), isTrue);
      expect(service.verifyPin('0000'), isFalse);
      expect(service.isCategoryLocked('live', '9'), isTrue);

      // ...and the plaintext copy is gone from disk after the migration.
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('pin_lock_v1_${account.key}')!;
      expect(raw, isNot(contains('9876')));
      final map = jsonDecode(raw) as Map<String, dynamic>;
      expect(map['pin'], isNull);
      expect((map['pinHash'] as String), isNotEmpty);
    });

    test('deleteFor clears persisted lock state', () async {
      final account = accountNamed('pin-delete');
      await service.loadFor(account);
      await service.setPin('1234');
      await service.deleteFor(account);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('pin_lock_v1_${account.key}'), isNull);
    });
  });
}
