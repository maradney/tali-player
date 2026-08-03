import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/features/auth/login_screen.dart';
import 'package:iptv_player/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The sign-in form has to survive a short viewport. It previously overflowed
/// by ~150px in landscape on a phone, which cut off the password field and the
/// sign-in button - the screen simply could not be used sideways. A debug-mode
/// overflow reports a Flutter error, so pumping at that size is itself the
/// assertion; the scroll check then proves the button is actually reachable
/// rather than merely un-clipped.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget wrap() => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const LoginScreen(),
      );

  /// Pixel 7 landscape: 2400x1080 physical at 2.625 dpr => 914x411 logical.
  void useLandscapePhone(WidgetTester tester) {
    tester.view.physicalSize = const Size(2400, 1080);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
  }

  testWidgets('does not overflow in landscape on a phone', (tester) async {
    useLandscapePhone(tester);
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    // An overflow would have been reported as a Flutter error by now.
    expect(tester.takeException(), isNull);
  });

  testWidgets('sign-in button is reachable in landscape', (tester) async {
    useLandscapePhone(tester);
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    final signIn = find.widgetWithText(FilledButton, 'Sign in');
    // Off-screen at this height - the point is that scrolling gets to it.
    await tester.scrollUntilVisible(
      signIn,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(signIn, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('still lays out on a tall phone without scrolling', (tester) async {
    // Portrait already worked; guard against the fix breaking the common case.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
