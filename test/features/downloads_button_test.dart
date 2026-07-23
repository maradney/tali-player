import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/features/common/downloads_button.dart';
import 'package:iptv_player/l10n/app_localizations.dart';

import '../support/test_support.dart';

void main() {
  testWidgets('shows a download icon and opens the Downloads screen on tap',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          appBar: AppBar(
            actions: [DownloadsButton(account: accountNamed('btn'))],
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.download_outlined), findsOneWidget);

    await tester.tap(find.byIcon(Icons.download_outlined));
    await tester.pumpAndSettle();

    // The Downloads screen is now on top, showing its (empty) state.
    expect(find.text('No downloads yet'), findsOneWidget);
  });
}
