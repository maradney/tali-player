import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/models/account.dart';
import 'package:iptv_player/data/models/channel.dart';
import 'package:iptv_player/data/models/movie.dart';
import 'package:iptv_player/data/models/series_info.dart';
import 'package:iptv_player/data/sources/m3u_media_source.dart';
import 'package:iptv_player/data/sources/media_source.dart';
import 'package:iptv_player/data/sources/xtream_media_source.dart';

void main() {
  const account = Account(
    name: 'X',
    serverUrl: 'http://example.com:8080',
    username: 'alice',
    password: 's3cret',
  );

  group('MediaSource.forAccount', () {
    test('returns an Xtream source for an Xtream account', () {
      final source = MediaSource.forAccount(account);
      expect(source, isA<XtreamMediaSource>());
      expect(source.account, account);
      expect(source.supportsAccountStatus, isTrue);
    });

    test('returns an M3U source for an M3U account', () {
      const m3u = Account.m3u(name: 'M', url: 'http://host/list.m3u8');
      final source = MediaSource.forAccount(m3u);
      expect(source, isA<M3uMediaSource>());
      expect(source.supportsAccountStatus, isFalse);
    });
  });

  group('XtreamMediaSource URL building', () {
    final source = XtreamMediaSource(account);

    test('live URL follows {server}/live/{user}/{pass}/{id}.ts', () {
      const channel = Channel(streamId: '5', name: 'CNN', categoryId: '1');
      expect(source.liveUrl(channel),
          'http://example.com:8080/live/alice/s3cret/5.ts');
    });

    test('vod URL uses the container extension', () {
      const movie = Movie(
        streamId: '9',
        name: 'Dune',
        categoryId: '2',
        containerExtension: 'mkv',
      );
      expect(source.vodUrl(movie),
          'http://example.com:8080/movie/alice/s3cret/9.mkv');
    });

    test('episode URL follows the series path', () {
      const episode = Episode(
        id: '42',
        title: 'Pilot',
        episodeNum: 1,
        containerExtension: 'mp4',
      );
      expect(source.episodeUrl(episode),
          'http://example.com:8080/series/alice/s3cret/42.mp4');
    });
  });
}
