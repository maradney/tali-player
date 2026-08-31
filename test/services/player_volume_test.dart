import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Volume is a property of the room you are sitting in, not of the video, so
/// it has to outlive both. It used to reset to full on every new episode.
void main() {
  final service = SettingsService.instance;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    service.resetForTesting();
  });

  test('defaults to full for someone who has never set it', () async {
    await service.loadFor('fresh');
    expect(service.playerVolume, 100);
  });

  test('a chosen level survives a reload', () async {
    await service.loadFor('p1');
    await service.setPlayerVolume(35);
    expect(service.playerVolume, 35);

    service.resetForTesting();
    await service.loadFor('p1');
    expect(service.playerVolume, 35,
        reason: 'the whole point: it must not snap back to 100');
  });

  test('silence is remembered too', () async {
    // Dragging the slider to zero is a deliberate choice and is kept. (Muting
    // via the button is separate and deliberately not persisted.)
    await service.loadFor('quiet');
    await service.setPlayerVolume(0);

    service.resetForTesting();
    await service.loadFor('quiet');
    expect(service.playerVolume, 0);
  });

  test('out-of-range values are clamped, not stored raw', () async {
    await service.loadFor('clamp');
    await service.setPlayerVolume(180);
    expect(service.playerVolume, 100);
    await service.setPlayerVolume(-20);
    expect(service.playerVolume, 0);
  });

  test('is per profile', () async {
    await service.loadFor('parent');
    await service.setPlayerVolume(20);

    await service.loadFor('kid');
    expect(service.playerVolume, 100, reason: 'a second profile gets its own');

    await service.loadFor('parent');
    expect(service.playerVolume, 20);
  });

  test('deleteFor removes it with the rest of a profile', () async {
    await service.loadFor('doomed');
    await service.setPlayerVolume(10);
    await service.deleteFor('doomed');

    service.resetForTesting();
    await service.loadFor('doomed');
    expect(service.playerVolume, 100);
  });
}
