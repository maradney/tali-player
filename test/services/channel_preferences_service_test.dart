import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/models/channel.dart';
import 'package:iptv_player/data/services/channel_preferences_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/test_support.dart';

Channel _ch(String id, String name) =>
    Channel(streamId: id, name: name, categoryId: '1');

void main() {
  final service = ChannelPreferencesService.instance;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  test('defaults: nothing hidden, provider-default order', () async {
    await service.loadFor(accountNamed('cp-default'));
    expect(service.sortOrder, ChannelSort.providerDefault);
    expect(service.hiddenCount, 0);
    expect(service.isHidden('1'), isFalse);
  });

  group('apply', () {
    final channels = [_ch('1', 'Zeta'), _ch('2', 'alpha'), _ch('3', 'Mike')];

    test('provider default preserves the original order', () async {
      await service.loadFor(accountNamed('cp-apply-default'));
      final out = service.apply(channels);
      expect(out.map((c) => c.streamId), ['1', '2', '3']);
    });

    test('name ascending is case-insensitive', () async {
      await service.loadFor(accountNamed('cp-apply-asc'));
      await service.setSortOrder(ChannelSort.nameAsc);
      final out = service.apply(channels);
      expect(out.map((c) => c.name), ['alpha', 'Mike', 'Zeta']);
    });

    test('name descending is case-insensitive', () async {
      await service.loadFor(accountNamed('cp-apply-desc'));
      await service.setSortOrder(ChannelSort.nameDesc);
      final out = service.apply(channels);
      expect(out.map((c) => c.name), ['Zeta', 'Mike', 'alpha']);
    });

    test('hidden channels are dropped, unless includeHidden', () async {
      await service.loadFor(accountNamed('cp-apply-hidden'));
      await service.setHidden('2', true);
      expect(service.apply(channels).map((c) => c.streamId), ['1', '3']);
      expect(service.apply(channels, includeHidden: true).map((c) => c.streamId),
          ['1', '2', '3']);
    });

    test('does not mutate the input list', () async {
      await service.loadFor(accountNamed('cp-apply-nomutate'));
      await service.setSortOrder(ChannelSort.nameAsc);
      final input = [_ch('1', 'Zeta'), _ch('2', 'alpha')];
      service.apply(input);
      expect(input.map((c) => c.streamId), ['1', '2']); // untouched
    });
  });

  group('hide', () {
    test('setHidden toggles and reports state', () async {
      await service.loadFor(accountNamed('cp-hide'));
      await service.setHidden('5', true);
      expect(service.isHidden('5'), isTrue);
      expect(service.hiddenCount, 1);
      await service.setHidden('5', false);
      expect(service.isHidden('5'), isFalse);
      expect(service.hiddenCount, 0);
    });
  });

  group('persistence', () {
    test('sort + hidden survive to shared_preferences', () async {
      final account = accountNamed('cp-persist');
      await service.loadFor(account);
      await service.setSortOrder(ChannelSort.nameDesc);
      await service.setHidden('9', true);

      final prefs = await SharedPreferences.getInstance();
      final map = jsonDecode(prefs.getString('channel_prefs_v1_${account.key}')!)
          as Map<String, dynamic>;
      expect(map['sort'], 'nameDesc');
      expect(map['hidden'], contains('9'));
    });

    test('loadFor restores stored preferences', () async {
      final account = accountNamed('cp-load');
      SharedPreferences.setMockInitialValues({
        'channel_prefs_v1_${account.key}':
            jsonEncode({'sort': 'nameAsc', 'hidden': ['3', '4']}),
      });
      await service.loadFor(account);
      expect(service.sortOrder, ChannelSort.nameAsc);
      expect(service.isHidden('3'), isTrue);
      expect(service.isHidden('4'), isTrue);
    });

    test('deleteFor wipes stored + in-memory prefs', () async {
      final account = accountNamed('cp-delete');
      await service.loadFor(account);
      await service.setHidden('1', true);
      await service.deleteFor(account);
      expect(service.hiddenCount, 0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('channel_prefs_v1_${account.key}'), isNull);
    });
  });
}
