import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/services/profiles_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final service = ProfilesService.instance;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    service.resetForTesting();
  });

  test('seeds a default profile on a fresh install', () async {
    await service.load();
    expect(service.profiles, hasLength(1));
    expect(service.activeProfileId, ProfilesService.defaultProfileId);
    expect(service.activeProfile?.name, ProfilesService.defaultProfileName);

    // Persisted so the next launch reads it back rather than re-seeding.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('profiles_v1'), hasLength(1));
    expect(prefs.getString('active_profile_id_v1'),
        ProfilesService.defaultProfileId);
  });

  test('addProfile appends and makes the new profile active', () async {
    await service.load();
    final kids = await service.addProfile(name: 'Kids');

    expect(service.profiles.map((p) => p.name), containsAll(['Default', 'Kids']));
    expect(service.activeProfileId, kids.id);
    expect(kids.hasPin, isFalse);
  });

  test('addProfile can mark a kids profile; it round-trips through storage',
      () async {
    await service.load();
    final kids = await service.addProfile(name: 'Kids', isKids: true);
    expect(kids.isKids, isTrue);
    expect(kids.hasPin, isFalse); // kids profiles are intentionally PIN-less

    // Reload from disk: the flag survives.
    service.resetForTesting();
    await service.load();
    final reloaded = service.profiles.firstWhere((p) => p.id == kids.id);
    expect(reloaded.isKids, isTrue);

    // A normal profile stays non-kids and omits the flag from its JSON.
    final normal = await service.addProfile(name: 'Dad');
    expect(normal.isKids, isFalse);
    expect(normal.toJson().containsKey('isKids'), isFalse);
  });

  test('a PIN is stored only as a salted hash, never in plaintext', () async {
    await service.load();
    final p = await service.addProfile(name: 'Locked', pin: '1234');

    expect(p.hasPin, isTrue);
    expect(p.pinHash, isNotNull);
    expect(p.pinHash, isNot(contains('1234')));

    final prefs = await SharedPreferences.getInstance();
    final blob = prefs.getStringList('profiles_v1')!.join();
    expect(blob, isNot(contains('"1234"')));

    expect(service.verifyPin(p.id, '1234'), isTrue);
    expect(service.verifyPin(p.id, '0000'), isFalse);
  });

  test('setPin / clearPin toggle protection', () async {
    await service.load();
    final id = service.activeProfileId!;
    expect(service.activeProfile!.hasPin, isFalse);

    await service.setPin(id, '9999');
    expect(service.activeProfile!.hasPin, isTrue);
    expect(service.verifyPin(id, '9999'), isTrue);

    await service.clearPin(id);
    expect(service.activeProfile!.hasPin, isFalse);
    expect(service.verifyPin(id, '9999'), isFalse);
  });

  test('renameProfile changes the label but keeps the id (and its data scope)',
      () async {
    await service.load();
    final id = service.activeProfileId!;
    await service.renameProfile(id, 'Living Room');
    expect(service.activeProfile!.name, 'Living Room');
    expect(service.activeProfileId, id); // scope unchanged
  });

  test('switchTo only changes to a known profile', () async {
    await service.load();
    const defaultId = ProfilesService.defaultProfileId;
    await service.addProfile(name: 'Other'); // becomes active

    await service.switchTo(defaultId);
    expect(service.activeProfileId, defaultId);

    await service.switchTo('nope');
    expect(service.activeProfileId, defaultId); // unchanged
  });

  test('removeProfile drops it and reassigns active', () async {
    await service.load();
    final a = await service.addProfile(name: 'A'); // active = A
    await service.removeProfile(a.id);

    expect(service.profiles.map((p) => p.id), isNot(contains(a.id)));
    expect(service.activeProfile, isNotNull);
  });

  test('removing the last profile re-seeds a default', () async {
    await service.load();
    // Remove the seeded default (the only one) — a fresh default appears.
    await service.removeProfile(service.activeProfileId!);
    expect(service.profiles, hasLength(1));
    expect(service.activeProfileId, ProfilesService.defaultProfileId);
  });

  test('load reads back persisted profiles without re-seeding', () async {
    SharedPreferences.setMockInitialValues({
      'profiles_v1': [
        jsonEncode({'id': 'p1', 'name': 'One'}),
        jsonEncode({'id': 'p2', 'name': 'Two'}),
      ],
      'active_profile_id_v1': 'p2',
    });
    service.resetForTesting();

    await service.load();
    expect(service.profiles.map((p) => p.id), ['p1', 'p2']);
    expect(service.activeProfileId, 'p2');
  });

  test('a stale active id falls back to the first profile', () async {
    SharedPreferences.setMockInitialValues({
      'profiles_v1': [jsonEncode({'id': 'p1', 'name': 'One'})],
      'active_profile_id_v1': 'gone',
    });
    service.resetForTesting();

    await service.load();
    expect(service.activeProfileId, 'p1');
  });
}
