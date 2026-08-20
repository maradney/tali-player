import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/models/playback_progress.dart';
import 'package:iptv_player/data/services/playback_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/test_support.dart';

/// What a series looks like in "continue watching" once an episode is
/// finished.
///
/// Finishing deletes the episode's progress, to stop a finished item asking
/// you to resume its credits. For a series that used to delete the only
/// record of where the viewer was: the detail screen lost its highlight and
/// its season, and the show left continue watching. The player now writes a
/// zero-position entry for the next episode, and these are the properties
/// that entry has to have for the rest of the app to read it correctly.
void main() {
  final service = PlaybackService.instance;

  PlaybackProgress pointerTo(String id, int season, int episode) =>
      PlaybackProgress(
        type: 'episode',
        id: id,
        position: Duration.zero,
        total: Duration.zero,
        seriesId: 'show-1',
        seasonNumber: season,
        episodeNum: episode,
        updatedAt: DateTime.now(),
      );

  /// A distinct account per test. PlaybackService is a singleton and loadFor
  /// short-circuits when the account key has not changed, so reusing one
  /// account carries _items from the previous test into the next — the
  /// isolation rule test_support.dart already documents.
  Future<void> useAccount(String name) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await service.loadFor(accountNamed(name));
  }

  test('a finished episode replaced by a pointer keeps the series findable',
      () async {
    await useAccount('finish-advance');
    await service.save(PlaybackProgress(
      type: 'episode',
      id: 's3e4',
      position: const Duration(minutes: 40),
      total: const Duration(minutes: 42),
      seriesId: 'show-1',
      seasonNumber: 3,
      episodeNum: 4,
      updatedAt: DateTime.now(),
    ));

    // What the player does on finishing: drop the episode, point at the next.
    await service.clear('episode', 's3e4');
    expect(service.lastEpisodeForSeries('show-1'), isNull,
        reason: 'setup: clearing alone is what used to lose the series');

    await service.save(pointerTo('s3e5', 3, 5));

    final last = service.lastEpisodeForSeries('show-1');
    expect(last, isNotNull, reason: 'the series must stay findable');
    expect(last!.id, 's3e5');
    expect(last.seasonNumber, 3);
    expect(last.episodeNum, 5);
  });

  test('the series counts as in progress but draws no progress bar', () async {
    await useAccount('no-bar');
    // Zero total means "nothing watched of it yet". A bar at 0% would claim
    // the viewer had started an episode they have not opened.
    await service.save(pointerTo('s3e5', 3, 5));

    expect(service.isInProgress('series', 'show-1'), isTrue);
    expect(service.progressFraction('series', 'show-1'), isNull);
  });

  test('a pointer across a season boundary carries the new season', () async {
    await useAccount('cross-season');
    // Finishing a season finale points at the next season's first episode,
    // which is what makes the detail screen open on the right tab.
    await service.save(pointerTo('s4e1', 4, 1));

    final last = service.lastEpisodeForSeries('show-1');
    expect(last!.seasonNumber, 4);
    expect(last.episodeNum, 1);
  });

  test('watching the pointed-at episode replaces the pointer with real progress',
      () async {
    await useAccount('real-progress');
    await service.save(pointerTo('s3e5', 3, 5));
    await service.save(PlaybackProgress(
      type: 'episode',
      id: 's3e5',
      position: const Duration(minutes: 5),
      total: const Duration(minutes: 42),
      seriesId: 'show-1',
      seasonNumber: 3,
      episodeNum: 5,
      updatedAt: DateTime.now(),
    ));

    expect(service.progressFraction('series', 'show-1'), closeTo(5 / 42, 0.001));
  });

  test('finishing the last episode leaves the series with nothing', () async {
    await useAccount('series-over');
    // No next episode means no pointer: the show is done and should leave
    // continue watching rather than linger.
    await service.save(pointerTo('final', 9, 10));
    await service.clear('episode', 'final');

    expect(service.lastEpisodeForSeries('show-1'), isNull);
    expect(service.isInProgress('series', 'show-1'), isFalse);
  });
}
