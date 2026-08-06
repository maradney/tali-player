import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/models/search_result.dart';
import 'package:iptv_player/features/home/home_shell.dart';

/// Splitting the nav destinations between the bottom bar and "More".
///
/// The app has ten destinations. All ten were rendered in a NavigationBar,
/// which on a ~410dp phone wrapped and clipped every label - "Movie s",
/// "Favorit es", "Histor y", with Search running off the edge of the screen.
void main() {
  final all = List.generate(10, (i) => i);

  test('caps the bar and puts the rest behind More', () {
    final split = splitDestinationsForBar(all);
    // 4 destinations + a More entry = 5 chips, the Material maximum.
    expect(split.bar.length, kMaxBottomBarDestinations - 1);
    expect(split.overflow, isNotEmpty);
  });

  test('keeps the content types people came for in the bar', () {
    // Home, Live TV, Movies, Series - indices 0-3.
    expect(splitDestinationsForBar(all).bar, [0, 1, 2, 3]);
  });

  test('every destination survives the split exactly once', () {
    // The bar and sheet together must still reach all ten; dropping one would
    // make a screen unreachable rather than merely awkward.
    final split = splitDestinationsForBar(all);
    expect([...split.bar, ...split.overflow], all);
  });

  test('no More entry when everything already fits', () {
    final few = [0, 1, 2, 6];
    final split = splitDestinationsForBar(few);
    expect(split.bar, few);
    expect(split.overflow, isEmpty);
  });

  test('exactly the maximum still fits without More', () {
    final exact = [0, 1, 2, 3, 6];
    expect(exact.length, kMaxBottomBarDestinations);
    final split = splitDestinationsForBar(exact);
    expect(split.bar, exact);
    expect(split.overflow, isEmpty);
  });

  test('an M3U playlist fits its whole nav in the bar', () {
    // M3U hides New/Browse/Watchlist/History/Search, leaving five - so a
    // phone on an M3U playlist should get no More entry at all.
    final visible = visibleDestinationIndices(
      10,
      {ContentType.live, ContentType.movie, ContentType.series},
      isM3u: true,
    );
    final split = splitDestinationsForBar(visible);
    expect(split.overflow, isEmpty,
        reason: 'M3U has ${visible.length} destinations: $visible');
    expect(split.bar, visible);
  });

  test('one destination is still valid', () {
    final split = splitDestinationsForBar([0]);
    expect(split.bar, [0]);
    expect(split.overflow, isEmpty);
  });
}
