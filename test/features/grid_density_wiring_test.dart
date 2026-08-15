import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/services/settings_service.dart';
import 'package:iptv_player/features/common/poster_grid.dart';
import 'package:iptv_player/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Grid density, end to end: the *setting* must change the rendered grid.
///
/// poster_grid_columns_test.dart already sweeps the column arithmetic from 200
/// to 2400px, so the maths is settled. What that cannot show is whether the
/// setting reaches the grid at all - a correct function nobody calls with the
/// user's choice would pass every one of those tests while the setting did
/// nothing on screen, which is exactly what the original bug looked like.
///
/// So this counts real tiles in a real GridView at the width where Comfortable
/// and Spacious used to collide.
///
/// That width has to be picked deliberately, not roughly. The grid takes 12pt
/// of padding either side, so the collision condition is on the *available*
/// width: ceil(800/200) and ceil(800/260) are both 4, which needs a widget
/// 824 wide. An earlier version of this file used 824's near neighbour 800,
/// where available is 776 and ceil() gives 6/4/3 - all distinct, so the test
/// passed against the very bug it was written to catch. Verified by restoring
/// ceil() and watching this fail.
void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    SettingsService.instance.resetForTesting();
    await SettingsService.instance.loadFor('default');
  });

  /// Renders the grid at [width] and returns the number of tiles on row one,
  /// counted from their painted positions rather than assumed.
  Future<int> columnsAt(WidgetTester tester, double width) async {
    // The default test surface is 800x600, which silently clamps a wider
    // SizedBox - the grid then lays out at 800 rather than the width being
    // asked about, and 800 is not a colliding width. Give it room first.
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final items = List.generate(24, (i) => 'Item $i');
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SizedBox(
          width: width,
          height: 900,
          child: PosterGrid<String>(
            items: items,
            titleOf: (s) => s,
            posterUrlOf: (_) => null,
            onTap: (_) {},
            idealTileWidth: SettingsService.instance.gridIdealTileWidth,
          ),
        ),
      ),
    ));
    await tester.pump();

    // Tiles sharing the smallest dy are the first row.
    final tops = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => tester.getTopLeft(find.text(t.data!)).dy)
        .toList();
    final firstRow = tops.reduce((a, b) => a < b ? a : b);
    return tops.where((t) => t == firstRow).length;
  }

  testWidgets('the three densities render differently at the collision width',
      (tester) async {
    final counts = <GridDensity, int>{};
    for (final density in GridDensity.values) {
      await SettingsService.instance.setGridDensity(density);
      counts[density] = await columnsAt(tester, 824);
    }

    expect(counts[GridDensity.compact]!,
        greaterThan(counts[GridDensity.comfortable]!),
        reason: 'compact vs comfortable: $counts');
    expect(counts[GridDensity.comfortable]!,
        greaterThan(counts[GridDensity.spacious]!),
        reason: 'comfortable vs spacious collided again: $counts');
  });

  testWidgets('changing the setting restyles an already-built grid',
      (tester) async {
    // The setting is read at build time, so a stale grid would keep the old
    // column count until the screen was rebuilt for some other reason.
    await SettingsService.instance.setGridDensity(GridDensity.spacious);
    final spacious = await columnsAt(tester, 824);

    await SettingsService.instance.setGridDensity(GridDensity.compact);
    final compact = await columnsAt(tester, 824);

    expect(compact, greaterThan(spacious), reason: '$compact vs $spacious');
  });
}
