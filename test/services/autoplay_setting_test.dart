import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The autoplay preference. Default-on was a deliberate choice, so it is
/// asserted rather than left to whatever the field initialiser happens to say.
void main() {
  final service = SettingsService.instance;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    service.resetForTesting();
  });

  test('defaults to on for a profile that has never set it', () async {
    await service.loadFor('fresh');
    expect(service.autoplayNextEpisode, isTrue);
  });

  test('turning it off survives a reload', () async {
    await service.loadFor('p1');
    await service.setAutoplayNextEpisode(false);
    expect(service.autoplayNextEpisode, isFalse);

    service.resetForTesting();
    await service.loadFor('p1');
    expect(service.autoplayNextEpisode, isFalse,
        reason: 'the off state must persist, not spring back to the default');
  });

  test('is per profile', () async {
    // Settings are profile-scoped; one person disabling autoplay must not
    // disable it for everyone else on the install.
    await service.loadFor('parent');
    await service.setAutoplayNextEpisode(false);

    await service.loadFor('kid');
    expect(service.autoplayNextEpisode, isTrue,
        reason: 'a second profile should still get the default');

    await service.loadFor('parent');
    expect(service.autoplayNextEpisode, isFalse);
  });

  test('deleteFor removes it with the rest of a profile', () async {
    await service.loadFor('doomed');
    await service.setAutoplayNextEpisode(false);
    await service.deleteFor('doomed');

    service.resetForTesting();
    await service.loadFor('doomed');
    expect(service.autoplayNextEpisode, isTrue,
        reason: 'a deleted profile must not leave settings behind');
  });
}
