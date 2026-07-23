import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/models/search_result.dart';
import 'package:iptv_player/features/home/home_shell.dart';

void main() {
  const total = 10; // Home, Live, Movies, Series, Recent, Browse, Fav, Watch, History, Search

  test('all types present → every destination is shown', () {
    final visible = visibleDestinationIndices(total, {
      ContentType.live,
      ContentType.movie,
      ContentType.series,
    });
    expect(visible, List.generate(total, (i) => i));
  });

  test('a channels-only playlist hides Movies (2) and Series (3)', () {
    final visible = visibleDestinationIndices(total, {ContentType.live});
    expect(visible, [0, 1, 4, 5, 6, 7, 8, 9]);
    expect(visible, isNot(contains(2)));
    expect(visible, isNot(contains(3)));
  });

  test('a VOD-only playlist hides Live (1)', () {
    final visible = visibleDestinationIndices(
        total, {ContentType.movie, ContentType.series});
    expect(visible, isNot(contains(1)));
    expect(visible, containsAll([2, 3]));
  });

  test('no types present still keeps the non-type destinations', () {
    final visible = visibleDestinationIndices(total, <ContentType>{});
    // Home(0), Recent(4), Browse(5), Favorites(6), Watchlist(7), History(8),
    // Search(9) never depend on a single content type.
    expect(visible, [0, 4, 5, 6, 7, 8, 9]);
  });

  test('M3U hides New/Browse/Watchlist/History/Search', () {
    final visible = visibleDestinationIndices(
      total,
      {ContentType.live, ContentType.movie, ContentType.series},
      isM3u: true,
    );
    // Only Home(0), Live(1), Movies(2), Series(3), Favorites(6).
    expect(visible, [0, 1, 2, 3, 6]);
  });

  test('M3U still hides empty content types too', () {
    final visible = visibleDestinationIndices(
      total,
      {ContentType.live}, // channels-only playlist
      isM3u: true,
    );
    expect(visible, [0, 1, 6]); // Home, Live, Favorites
  });

  group('effectiveSelectedIndex', () {
    test('keeps the selection when its destination is still visible', () {
      expect(effectiveSelectedIndex(6, [0, 1, 2, 3, 6]), 6);
    });

    test('falls back to the first visible destination when hidden', () {
      // Regression: on Search (9), switching to an M3U account hides Search;
      // the shell used to keep showing it while highlighting Home.
      expect(effectiveSelectedIndex(9, [0, 1, 2, 3, 6]), 0);
    });
  });
}
