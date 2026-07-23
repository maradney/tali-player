import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/models/m3u_entry.dart';
import 'package:iptv_player/data/sources/m3u_parser.dart';

void main() {
  group('M3uParser.parse', () {
    test('reads header EPG url, entry attributes, and the stream url', () {
      const text = '#EXTM3U url-tvg="http://host/epg.xml"\n'
          '#EXTINF:-1 tvg-id="cnn.us" tvg-logo="http://host/cnn.png" '
          'group-title="News",CNN HD\n'
          'http://host/live/u/p/5.ts';
      final playlist = M3uParser.parse(text);

      expect(playlist.epgUrl, 'http://host/epg.xml');
      expect(playlist.entries, hasLength(1));
      final e = playlist.entries.single;
      expect(e.kind, M3uEntryKind.live);
      expect(e.name, 'CNN HD');
      expect(e.tvgId, 'cnn.us');
      expect(e.logoUrl, 'http://host/cnn.png');
      expect(e.groupTitle, 'News');
      expect(e.url, 'http://host/live/u/p/5.ts');
      expect(e.containerExtension, isNull); // live carries none
    });

    test('classifies a .mp4 / /movie/ entry as a movie with its extension', () {
      const text = '#EXTINF:-1 group-title="Movies",The Matrix (1999)\n'
          'http://host/movie/u/p/42.mkv';
      final e = M3uParser.parse(text).entries.single;
      expect(e.kind, M3uEntryKind.movie);
      expect(e.containerExtension, 'mkv');
      expect(e.seriesName, isNull);
    });

    test('classifies S01E02 as an episode and extracts series/season/number',
        () {
      const text = '#EXTINF:-1,Dark S01E02 Lies\n'
          'http://host/series/u/p/77.mp4';
      final e = M3uParser.parse(text).entries.single;
      expect(e.kind, M3uEntryKind.episode);
      expect(e.seriesName, 'Dark');
      expect(e.seasonNumber, 1);
      expect(e.episodeNumber, 2);
      expect(e.containerExtension, 'mp4');
    });

    test('a /series/ path without a parseable number falls back to movie', () {
      const text = '#EXTINF:-1,Random Documentary\n'
          'http://host/series/u/p/9.mp4';
      final e = M3uParser.parse(text).entries.single;
      expect(e.kind, M3uEntryKind.movie);
    });

    test('recognizes the 1x02 and Season/Episode forms', () {
      const text = '#EXTINF:-1,Friends 2x05\nhttp://host/series/u/p/1.mp4\n'
          '#EXTINF:-1,Lost Season 3 Episode 8\nhttp://host/series/u/p/2.mp4';
      final entries = M3uParser.parse(text).entries;
      expect(entries[0].seriesName, 'Friends');
      expect(entries[0].seasonNumber, 2);
      expect(entries[0].episodeNumber, 5);
      expect(entries[1].seriesName, 'Lost');
      expect(entries[1].seasonNumber, 3);
      expect(entries[1].episodeNumber, 8);
    });

    test('a resolution like 1920x1080 is not mistaken for an episode', () {
      const text = '#EXTINF:-1,Sports Channel 1920x1080\nhttp://host/live/u/p/3.ts';
      final e = M3uParser.parse(text).entries.single;
      expect(e.kind, M3uEntryKind.live);
      expect(e.seasonNumber, isNull);
    });

    test('splits the display name at the first UNQUOTED comma', () {
      const text = '#EXTINF:-1 group-title="News, Sports",CNN\n'
          'http://host/live/u/p/5.ts';
      final e = M3uParser.parse(text).entries.single;
      expect(e.groupTitle, 'News, Sports');
      expect(e.name, 'CNN');
    });

    test('falls back to tvg-name when the display name is empty', () {
      const text = '#EXTINF:-1 tvg-name="BBC One",\nhttp://host/live/u/p/5.ts';
      expect(M3uParser.parse(text).entries.single.name, 'BBC One');
    });

    test('captures #EXTVLCOPT headers and #EXTGRP group fallback', () {
      const text = '#EXTINF:-1,Channel\n'
          '#EXTVLCOPT:http-user-agent=Mozilla/5.0\n'
          '#EXTGRP:Sports\n'
          'http://host/live/u/p/5.ts';
      final e = M3uParser.parse(text).entries.single;
      expect(e.vlcOpts['http-user-agent'], 'Mozilla/5.0');
      expect(e.groupTitle, 'Sports');
    });

    test('group-title wins over a later #EXTGRP', () {
      const text = '#EXTINF:-1 group-title="Primary",Ch\n'
          '#EXTGRP:Secondary\nhttp://host/live/u/p/5.ts';
      expect(M3uParser.parse(text).entries.single.groupTitle, 'Primary');
    });

    test('skips a trailing #EXTINF with no url and tolerates blank lines', () {
      const text = '#EXTM3U\n\n'
          '#EXTINF:-1,Good\nhttp://host/live/u/p/1.ts\n\n'
          '#EXTINF:-1,Dangling';
      final entries = M3uParser.parse(text).entries;
      expect(entries, hasLength(1));
      expect(entries.single.name, 'Good');
    });

    test('handles CRLF line endings', () {
      const text = '#EXTM3U\r\n#EXTINF:-1,Ch\r\nhttp://host/live/u/p/1.ts\r\n';
      expect(M3uParser.parse(text).entries.single.name, 'Ch');
    });

    test('reads x-tvg-url and takes the first of a comma-separated list', () {
      const text = '#EXTM3U x-tvg-url="http://a/epg.xml,http://b/epg.xml"\n'
          '#EXTINF:-1,Ch\nhttp://host/live/u/p/1.ts';
      expect(M3uParser.parse(text).epgUrl, 'http://a/epg.xml');
    });

    test('non-M3U text yields an empty playlist rather than throwing', () {
      final playlist = M3uParser.parse('just some random text\nnot a playlist');
      expect(playlist.isEmpty, isTrue);
      expect(playlist.epgUrl, isNull);
    });
  });

  group('M3uParser.extensionOf', () {
    test('reads the last-segment extension, ignoring a query string', () {
      expect(M3uParser.extensionOf('http://h/a/42.mp4?token=x'), 'mp4');
      expect(M3uParser.extensionOf('http://h/live/5.ts'), 'ts');
    });

    test('returns null when there is no plausible extension', () {
      expect(M3uParser.extensionOf('http://h/live/u/p/5'), isNull);
      expect(M3uParser.extensionOf('http://h/stream/'), isNull);
    });
  });
}
