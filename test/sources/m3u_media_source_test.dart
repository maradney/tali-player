import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/models/account.dart';
import 'package:iptv_player/data/models/channel.dart';
import 'package:iptv_player/data/sources/m3u_media_source.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/test_support.dart';

const _playlist = '#EXTM3U url-tvg="http://host/epg.xml"\n'
    '#EXTINF:-1 tvg-id="cnn" tvg-logo="http://host/cnn.png" group-title="News",CNN\n'
    'http://host/live/u/p/5.ts\n'
    '#EXTINF:-1 group-title="Movies",Dune\n'
    'http://host/movie/u/p/9.mkv\n'
    '#EXTINF:-1 group-title="Shows",Dark S01E01\n'
    'http://host/series/u/p/1.mp4\n'
    '#EXTINF:-1 group-title="Shows",Dark S01E02\n'
    'http://host/series/u/p/2.mp4';

void main() {
  const account = Account.m3u(name: 'Test', url: 'http://host/list.m3u8');

  M3uMediaSource sourceReturning(String text) =>
      M3uMediaSource(account, fetch: (_) async => text);

  setUpAll(() async {
    await initDbEnvironment();
  });

  // Fresh prefs each test so the EPG-refresh timestamp doesn't leak between
  // tests (they share one account key).
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('after refresh()', () {
    late M3uMediaSource source;

    setUp(() async {
      source = sourceReturning(_playlist);
      await source.refresh();
    });

    test('browses live channels by group with their direct url', () async {
      final categories = await source.getLiveCategories();
      expect(categories.map((c) => c.categoryName), contains('News'));

      final channels = await source.getLiveStreams('News');
      expect(channels, hasLength(1));
      expect(channels.single.name, 'CNN');
      expect(source.liveUrl(channels.single), 'http://host/live/u/p/5.ts');
    });

    test('browses movies with their container extension + url', () async {
      final movies = await source.getVodStreams('Movies');
      expect(movies.single.name, 'Dune');
      expect(movies.single.containerExtension, 'mkv');
      expect(source.vodUrl(movies.single), 'http://host/movie/u/p/9.mkv');
    });

    test('reconstructs a series with its episodes and episode urls', () async {
      final series = await source.getSeries('Shows');
      expect(series.single.name, 'Dark');

      final info = await source.getSeriesInfo(series.single.seriesId);
      expect(info.seasons, hasLength(1));
      final episodes = info.seasons.single.episodes;
      expect(episodes, hasLength(2));
      expect(episodes.first.episodeNum, 1);
      expect(source.episodeUrl(episodes.first), 'http://host/series/u/p/1.mp4');
    });

    test('has no account status (unsupported)', () {
      expect(source.supportsAccountStatus, isFalse);
      expect(source.getAccountStatus, throwsUnsupportedError);
    });
  });

  group('resolveChannel', () {
    // CNN carries an #EXTVLCOPT User-Agent so headers restoration is covered.
    const playlist = '#EXTM3U\n'
        '#EXTINF:-1 tvg-logo="http://host/cnn.png" group-title="News",CNN\n'
        '#EXTVLCOPT:http-user-agent=SpecialAgent/1.0\n'
        'http://host/live/u/p/5.ts';

    late M3uMediaSource source;
    late Channel real;

    setUp(() async {
      source = sourceReturning(playlist);
      await source.refresh();
      real = (await source.getLiveStreams('News')).single;
    });

    test('restores url + headers on a snapshot-rebuilt channel', () async {
      // A favorite/history snapshot keeps only id/name/logo — no url.
      final snapshot = Channel(
        streamId: real.streamId,
        name: real.name,
        categoryId: '',
        logoUrl: real.logoUrl,
      );
      expect(source.liveUrl(snapshot), '');

      final resolved = await source.resolveChannel(snapshot);
      expect(source.liveUrl(resolved), 'http://host/live/u/p/5.ts');
      expect(resolved.headers, {'User-Agent': 'SpecialAgent/1.0'});
      expect(resolved.name, 'CNN');
      expect(resolved.categoryId, 'News'); // backfilled from the catalog
    });

    test('returns a channel with a url unchanged', () async {
      expect(await source.resolveChannel(real), same(real));
    });

    test('returns an unknown channel as-is (gone from the playlist)',
        () async {
      const gone = Channel(streamId: 'nope', name: 'Gone', categoryId: '');
      final resolved = await source.resolveChannel(gone);
      expect(source.liveUrl(resolved), '');
    });
  });

  test('validate throws when the playlist has no entries', () {
    expect(sourceReturning('not a playlist').validate(),
        throwsA(isA<M3uException>()));
  });

  test('validate passes for a playlist with entries', () async {
    await expectLater(sourceReturning(_playlist).validate(), completes);
  });

  test('serves EPG for a channel matched to the XMLTV feed by tvg-id', () async {
    String xmltvTime(DateTime dt) {
      final u = dt.toUtc();
      String two(int n) => n.toString().padLeft(2, '0');
      return '${u.year}${two(u.month)}${two(u.day)}'
          '${two(u.hour)}${two(u.minute)}${two(u.second)} +0000';
    }

    final now = DateTime.now();
    final xmltv = '<tv>'
        '<programme channel="cnn" start="${xmltvTime(now.subtract(const Duration(minutes: 30)))}" '
        'stop="${xmltvTime(now.add(const Duration(minutes: 30)))}"><title>Now Show</title></programme>'
        '<programme channel="cnn" start="${xmltvTime(now.add(const Duration(minutes: 30)))}" '
        'stop="${xmltvTime(now.add(const Duration(minutes: 90)))}"><title>Next Show</title></programme>'
        '</tv>';

    // The playlist's url-tvg points at .../epg.xml; route that url to the XMLTV.
    final source = M3uMediaSource(account,
        fetch: (url) async => url.contains('epg') ? xmltv : _playlist);
    await source.refresh();

    final channels = await source.getLiveStreams('News');
    final epg = await source.getShortEpg(channels.single.streamId);
    expect(epg.map((p) => p.title), ['Now Show', 'Next Show']);
    expect(epg.first.start.isBefore(now), isTrue);
  });

  test('does not refetch the EPG within the refresh interval', () async {
    var epgFetches = 0;
    final source = M3uMediaSource(account, fetch: (url) async {
      if (url.contains('epg')) {
        epgFetches++;
        return '<tv></tv>';
      }
      return _playlist;
    });
    await source.refresh();
    await source.refresh(); // within the interval — reuses the stored guide
    expect(epgFetches, 1);
  });

  test('channels with no tvg-id match return no EPG', () async {
    // This playlist channel has no tvg-id, so nothing lines up.
    const noId = '#EXTM3U\n#EXTINF:-1 group-title="News",Local\n'
        'http://host/live/u/p/9.ts';
    final source = M3uMediaSource(account, fetch: (_) async => noId);
    await source.refresh();
    final channels = await source.getLiveStreams('News');
    expect(await source.getShortEpg(channels.single.streamId), isEmpty);
  });
}
