import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/services/profiles_service.dart';
import 'package:iptv_player/features/profiles/profile_switching.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The rule that keeps a kids profile out of profile management — and so out of
/// its own allowed-content list, profile deletion, and PIN changes. Tested
/// directly (no widget tree) because this decision, not the dialog around it,
/// is what actually protects the feature.
void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    ProfilesService.instance.resetForTesting();
    await ProfilesService.instance.load(); // active = 'default', not kids
  });

  tearDown(() => ProfilesService.instance.resetForTesting());

  test('no gate for a normal profile, even with a PIN-protected sibling',
      () async {
    final other = await ProfilesService.instance.addProfile(name: 'Parent');
    await ProfilesService.instance.setPin(other.id, '1234');
    // addProfile made 'Parent' active; it isn't a kids profile.
    expect(parentGateRequired(), isFalse);
  });

  test('a kids profile is gated when a parent profile has a PIN', () async {
    final parent = ProfilesService.instance.profiles.first;
    await ProfilesService.instance.setPin(parent.id, '1234');
    await ProfilesService.instance.addProfile(name: 'Kids', isKids: true);

    expect(ProfilesService.instance.activeProfile?.isKids, isTrue);
    expect(parentGateRequired(), isTrue);
  });

  test('a kids profile is NOT gated when no parent profile has a PIN',
      () async {
    // Deliberate: with no parent PIN anywhere there is nothing to verify
    // against, and the child could just pick the unprotected profile from the
    // picker. Gating here would only lock a PIN-less parent out of their own
    // settings. This is the gap the kids-setup nudge exists to close.
    await ProfilesService.instance.addProfile(name: 'Kids', isKids: true);

    expect(ProfilesService.instance.activeProfile?.isKids, isTrue);
    expect(parentGateRequired(), isFalse);
  });

  test('the gate follows the active profile across a switch', () async {
    final parent = ProfilesService.instance.profiles.first;
    await ProfilesService.instance.setPin(parent.id, '1234');
    final kids =
        await ProfilesService.instance.addProfile(name: 'Kids', isKids: true);
    expect(parentGateRequired(), isTrue);

    await ProfilesService.instance.switchTo(parent.id);
    expect(parentGateRequired(), isFalse); // parent is in, no gate

    await ProfilesService.instance.switchTo(kids.id);
    expect(parentGateRequired(), isTrue); // back to the child, gated again
  });
}
