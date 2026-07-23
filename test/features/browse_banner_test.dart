import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/features/browse/browse_screen.dart';

void main() {
  group('computeBrowseBanner', () {
    test('off + no progress counted yet -> none', () {
      expect(
        computeBrowseBanner(
            enhancedSearchOn: false, running: false, progress: null),
        BrowseBanner.none,
      );
    });

    test('off + un-enriched titles remain -> nudge to enable', () {
      expect(
        computeBrowseBanner(
            enhancedSearchOn: false,
            running: false,
            progress: (enriched: 10, total: 40)),
        BrowseBanner.enableForMore,
      );
    });

    test('off + everything already enriched -> none (nothing more to get)', () {
      expect(
        computeBrowseBanner(
            enhancedSearchOn: false,
            running: false,
            progress: (enriched: 40, total: 40)),
        BrowseBanner.none,
      );
    });

    test('on + more to index -> indexing hint', () {
      expect(
        computeBrowseBanner(
            enhancedSearchOn: true,
            running: false,
            progress: (enriched: 10, total: 40)),
        BrowseBanner.indexing,
      );
    });

    test('on + complete -> none', () {
      expect(
        computeBrowseBanner(
            enhancedSearchOn: true,
            running: false,
            progress: (enriched: 40, total: 40)),
        BrowseBanner.none,
      );
    });

    test('running with no counts yet -> indexing', () {
      expect(
        computeBrowseBanner(
            enhancedSearchOn: true, running: true, progress: null),
        BrowseBanner.indexing,
      );
    });

    test('a crawl still finishing after the flag was flipped off -> indexing',
        () {
      // running wins: work is genuinely in flight, so "more coming" is true.
      expect(
        computeBrowseBanner(
            enhancedSearchOn: false,
            running: true,
            progress: (enriched: 10, total: 40)),
        BrowseBanner.indexing,
      );
    });
  });
}
