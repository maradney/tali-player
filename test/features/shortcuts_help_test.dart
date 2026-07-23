import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/features/player/shortcuts_help.dart';
import 'package:iptv_player/l10n/app_localizations.dart';

Future<void> _open(WidgetTester tester, {required bool isVod}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showShortcutsHelp(context, isVod: isVod),
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
  });
}
