import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/features/player/shortcuts_help.dart';
import 'package:iptv_player/l10n/app_localizations.dart';

Future<void> _open(
  WidgetTester tester, {
  required bool isVod,
  bool isSeries = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showShortcutsHelp(context, isVod: isVod, isSeries: isSeries),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('VOD shows the speed shortcut, not the channel one',
      (tester) async {
    await _open(tester, isVod: true);
    expect(find.text('['), findsOneWidget); // speed key cap
    expect(find.text(']'), findsOneWidget);
    expect(find.text('Page Up'), findsNothing); // live-only
  });

  testWidgets('live shows the channel shortcut, not the speed one',
      (tester) async {
    await _open(tester, isVod: false);
    expect(find.text('Page Up'), findsOneWidget);
    expect(find.text('Page Down'), findsOneWidget);
    expect(find.text('['), findsNothing); // VOD-only
  });

  testWidgets('always lists the universal shortcuts', (tester) async {
    await _open(tester, isVod: true);
    expect(find.text('Space'), findsOneWidget);
    expect(find.text('?'), findsOneWidget); // the help shortcut itself
    // Fullscreen applies to live and on-demand alike, so it is unconditional.
    expect(find.text('F'), findsOneWidget);
    expect(find.text('Esc'), findsOneWidget);
  });

  testWidgets('live lists fullscreen too', (tester) async {
    await _open(tester, isVod: false);
    expect(find.text('F'), findsOneWidget);
    expect(find.text('Esc'), findsOneWidget);
  });

  testWidgets('a movie does not list episode keys', (tester) async {
    // Listing keys that do nothing sends people pressing them and concluding
    // the player is broken.
    await _open(tester, isVod: true);
    expect(find.text('Shift+N'), findsNothing);
    expect(find.text('Shift+P'), findsNothing);
  });

  testWidgets('a series lists episode keys', (tester) async {
    await _open(tester, isVod: true, isSeries: true);
    expect(find.text('Shift+N'), findsOneWidget);
    expect(find.text('Shift+P'), findsOneWidget);
  });
}
