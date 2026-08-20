import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/models/series_info.dart';
import 'package:iptv_player/features/series/episode_navigator.dart';

/// Ordering rules for episode next/previous.
///
/// The two notions of "next" are the point of this file: autoplay stops at a
/// season finale, the Next button does not. Both are asserted, including that
/// they disagree at exactly one place - the last episode of a season.
Episode _ep(String id, int num) =>
    Episode(id: id, title: 'E$num', episodeNum: num, containerExtension: 'mp4');

Season _season(int number, List<Episode> episodes) =>
    Season(seasonNumber: number, name: 'S$number', episodes: episodes);

void main() {
  /// Two seasons of two, the ordinary case.
  final simple = EpisodeNavigator([
    _season(1, [_ep('101', 1), _ep('102', 2)]),
    _season(2, [_ep('201', 1), _ep('202', 2)]),
  ]);

  group('locating', () {
    test('finds an episode by id', () {
      expect(simple.locate('201'), const EpisodeCursor(1, 0));
    });

    test('returns null for an episode from another series', () {
      expect(simple.locate('999'), isNull);
    });
  });

  group('next', () {
    test('moves within a season', () {
      expect(simple.next(const EpisodeCursor(0, 0)), const EpisodeCursor(0, 1));
    });

    test('crosses into the next season, landing on its first episode', () {
      // The explicit ask: Next at a season finale opens S2E1.
      expect(simple.next(const EpisodeCursor(0, 1)), const EpisodeCursor(1, 0));
    });

    test('is null at the last episode of the final season', () {
      expect(simple.next(const EpisodeCursor(1, 1)), isNull);
      expect(simple.hasNext(const EpisodeCursor(1, 1)), isFalse);
    });
  });

  group('previous', () {
    test('moves within a season', () {
      expect(simple.previous(const EpisodeCursor(1, 1)),
          const EpisodeCursor(1, 0));
    });

    test('crosses back to the LAST episode of the previous season', () {
      // Not its first: what precedes S2E1 in viewing order is S1's finale.
      expect(simple.previous(const EpisodeCursor(1, 0)),
          const EpisodeCursor(0, 1));
    });

    test('is null at the first episode of the first season', () {
      expect(simple.previous(const EpisodeCursor(0, 0)), isNull);
      expect(simple.hasPrevious(const EpisodeCursor(0, 0)), isFalse);
    });
  });

  group('autoplay is season-bounded', () {
    test('rolls on mid-season', () {
      expect(simple.shouldAutoplayAfter(const EpisodeCursor(0, 0)), isTrue);
      expect(simple.nextInSeason(const EpisodeCursor(0, 0)),
          const EpisodeCursor(0, 1));
    });

    test('stops at a season finale even though Next would continue', () {
      // The one place the two disagree, which is the whole design.
      const finale = EpisodeCursor(0, 1);
      expect(simple.shouldAutoplayAfter(finale), isFalse);
      expect(simple.nextInSeason(finale), isNull);
      expect(simple.next(finale), isNotNull);
    });

    test('stops at the end of the series', () {
      expect(simple.shouldAutoplayAfter(const EpisodeCursor(1, 1)), isFalse);
    });
  });

  group('awkward panels', () {
    test('season 0 is an ordinary season, so it precedes season 1', () {
      // Panels expose specials as season 0. Treated as the panel presents it:
      // Previous from S1E1 goes into the specials, and season 0's first
      // episode is where the chain actually starts.
      final withSpecials = EpisodeNavigator([
        _season(0, [_ep('001', 1)]),
        _season(1, [_ep('101', 1)]),
      ]);
      expect(withSpecials.previous(const EpisodeCursor(1, 0)),
          const EpisodeCursor(0, 0));
      expect(withSpecials.previous(const EpisodeCursor(0, 0)), isNull);
      expect(withSpecials.next(const EpisodeCursor(0, 0)),
          const EpisodeCursor(1, 0));
    });

    test('an empty season in the middle is stepped over, not treated as an end',
        () {
      // A listed-but-empty season is a hole in the data, not the end of the
      // series; reporting "no next episode" there would strand the viewer.
      final gap = EpisodeNavigator([
        _season(1, [_ep('101', 1)]),
        _season(2, const []),
        _season(3, [_ep('301', 1)]),
      ]);
      expect(gap.next(const EpisodeCursor(0, 0)), const EpisodeCursor(2, 0));
      expect(gap.previous(const EpisodeCursor(2, 0)), const EpisodeCursor(0, 0));
    });

    test('episode numbers are never used as ordering', () {
      // Numbering that repeats across a season would make arithmetic on
      // episodeNum jump to the wrong place; position in the list is the truth.
      final odd = EpisodeNavigator([
        _season(1, [_ep('a', 5), _ep('b', 5), _ep('c', 1)]),
      ]);
      expect(odd.next(const EpisodeCursor(0, 0)), const EpisodeCursor(0, 1));
      expect(odd.next(const EpisodeCursor(0, 1)), const EpisodeCursor(0, 2));
      expect(odd.episodeAt(const EpisodeCursor(0, 2))!.id, 'c');
    });

    test('a single-episode series has neither direction', () {
      final one = EpisodeNavigator([
        _season(1, [_ep('only', 1)]),
      ]);
      expect(one.hasNext(const EpisodeCursor(0, 0)), isFalse);
      expect(one.hasPrevious(const EpisodeCursor(0, 0)), isFalse);
      expect(one.shouldAutoplayAfter(const EpisodeCursor(0, 0)), isFalse);
    });

    test('a series with no seasons at all answers safely', () {
      const empty = EpisodeNavigator([]);
      expect(empty.locate('1'), isNull);
      expect(empty.next(const EpisodeCursor(0, 0)), isNull);
      expect(empty.previous(const EpisodeCursor(0, 0)), isNull);
      expect(empty.episodeAt(const EpisodeCursor(0, 0)), isNull);
    });
  });

  group('walking the whole series', () {
    test('next reaches every episode in order, then stops', () {
      final seen = <String>[];
      var c = const EpisodeCursor(0, 0);
      seen.add(simple.episodeAt(c)!.id);
      while (simple.next(c) != null) {
        c = simple.next(c)!;
        seen.add(simple.episodeAt(c)!.id);
      }
      expect(seen, ['101', '102', '201', '202']);
    });

    test('previous walks back the same path', () {
      final seen = <String>[];
      var c = const EpisodeCursor(1, 1);
      seen.add(simple.episodeAt(c)!.id);
      while (simple.previous(c) != null) {
        c = simple.previous(c)!;
        seen.add(simple.episodeAt(c)!.id);
      }
      expect(seen, ['202', '201', '102', '101']);
    });
  });
}
