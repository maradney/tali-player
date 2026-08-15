import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/services/profiles_service.dart';
import 'package:iptv_player/features/auth/login_screen.dart';
import 'package:iptv_player/features/profiles/profile_picker_screen.dart';
import 'package:iptv_player/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Entering a profile that has no playlist yet used to be a dead end.
///
/// The picker reaches the login screen with pushAndRemoveUntil, so it is the
/// entire navigation stack: nothing to pop, and no app bar was drawn at all.
/// A freshly created kids profile is always in exactly that state, so a parent
/// who tapped into one before adding its playlist had no route back to their
/// own profile short of restarting the app.
///
/// The arrow is deliberately conditional. On a single-profile install there is
/// nowhere to go back *to*, and an arrow leading to a one-item picker would be
/// a dead end of its own - hence the control test below.
void main() {
  Widget app(Widget home) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      );

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    ProfilesService.instance.resetForTesting();
    await ProfilesService.instance.load();
  });

  testWidgets('a second profile with no playlist can get back to the picker',
      (tester) async {
    await ProfilesService.instance.addProfile(name: 'Kids');

    await tester.pumpWidget(app(const LoginScreen()));
    await tester.pumpAndSettle();

    final back = find.byIcon(Icons.arrow_back);
    expect(back, findsOneWidget, reason: 'no way out of an empty profile');

    await tester.tap(back);
    await tester.pumpAndSettle();

    expect(find.byType(ProfilePickerScreen), findsOneWidget);
    // pushAndRemoveUntil, not push: the login screen must not linger beneath.
    expect(find.byType(LoginScreen), findsNothing);
  });

  testWidgets('the only profile on the install gets no arrow', (tester) async {
    // Control. Without this, the test above would still pass if the arrow were
    // shown unconditionally - which would just relocate the dead end.
    expect(ProfilesService.instance.profiles, hasLength(1));

    await tester.pumpWidget(app(const LoginScreen()));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.arrow_back), findsNothing);
    expect(find.byType(AppBar), findsNothing,
        reason: 'a bar with nothing in it is just wasted height');
  });

  testWidgets('add-playlist mode keeps its own app bar instead', (tester) async {
    // Pushed on top of the app from AccountsScreen, so it is an ordinary route
    // with ordinary back behaviour - the switch-profile arrow would be wrong
    // here even though there are two profiles.
    await ProfilesService.instance.addProfile(name: 'Kids');

    await tester.pumpWidget(app(LoginScreen(onAdded: () {})));
    await tester.pumpAndSettle();

    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back), findsNothing,
        reason: 'this bar pops its route; it is not the profile switcher');
  });
}
