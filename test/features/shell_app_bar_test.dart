import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/models/account.dart';
import 'package:iptv_player/features/home/home_shell.dart';
import 'package:iptv_player/l10n/app_localizations.dart';

/// Switching tabs on a phone left the shell's app bar the wrong colour until
/// you scrolled the new tab down and back up: scroll Movies, switch to Series,
/// and the bar kept Movies' scrolled-under tint.
///
/// The shell bar sits above each screen's own app bar, so content never scrolls
/// under it and it should not react to scrolling at all. It did because a
/// Scaffold wraps its entire subtree - app bar included - in a
/// ScrollNotificationObserver, and observers pass notifications upward, so
/// every tab's scrolling reached it regardless of what sat in between.
void main() {
  const account = Account(
    name: 'Test playlist',
    serverUrl: 'http://example.com:8080',
    username: 'u',
    password: 'p',
  );

  /// The colour the app bar actually paints - AppBar's outermost Material.
  Color? barColor(WidgetTester tester) {
    final material = find
        .descendant(of: find.byType(AppBar), matching: find.byType(Material))
        .first;
    return tester.widget<Material>(material).color;
  }

  Widget host(PreferredSizeWidget bar) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          appBar: bar,
          body: ListView(
            children: [
              for (var i = 0; i < 60; i++)
                SizedBox(height: 60, child: Text('row $i')),
            ],
          ),
        ),
      );

  Future<Color?> colorAfterScrollingDown(
      WidgetTester tester, PreferredSizeWidget bar) async {
    await tester.pumpWidget(host(bar));
    await tester.pumpAndSettle();
    final before = barColor(tester);
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(barColor(tester), isNotNull, reason: 'no app bar Material found');
    return before;
  }

  testWidgets('shell bar keeps its colour when content scrolls under',
      (tester) async {
    final bar = ShellAppBar(
      account: account,
      onOpenAccounts: () {},
      onSwitchProfile: () {},
      onOpenSettings: () {},
      onOpenAbout: () {},
    );
    final before = await colorAfterScrollingDown(tester, bar);

    // Never tinting is what makes the stale tint impossible: with no scroll
    // state to hold, there is nothing left over for the next tab to inherit.
    expect(barColor(tester), before,
        reason: 'shell bar still reacts to scrolling, so it can go stale '
            'when the tab changes');
  });

  testWidgets('a plain AppBar in the same position does change colour',
      (tester) async {
    // Guards the test above from passing vacuously: if a scrolled-under tint
    // stopped being detectable this way, this one fails and says so.
    final before = await colorAfterScrollingDown(
        tester, AppBar(title: const Text('plain')));

    expect(barColor(tester), isNot(before),
        reason: 'the scrolled-under tint is no longer observable through '
            "AppBar's Material colour - the sibling test proves nothing");
  });
}
