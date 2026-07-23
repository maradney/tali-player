import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/features/player/audio_only_visualizer.dart';
import 'package:iptv_player/l10n/app_localizations.dart';

void main() {
  testWidgets('shows the stream title, radio icon, and audio-only label',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: AudioOnlyVisualizer(title: 'Jazz FM')),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Jazz FM'), findsOneWidget);
    expect(find.byIcon(Icons.radio), findsOneWidget);
    final l = lookupAppLocalizations(const Locale('en'));
    expect(find.text(l.audioOnlyStream), findsOneWidget);
    // The equalizer animates without throwing across frames.
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
  });
}
