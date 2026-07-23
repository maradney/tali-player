import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/models/m3u_entry.dart';
import 'package:iptv_player/data/models/search_result.dart';
import 'package:iptv_player/data/sources/m3u_catalog_builder.dart';

void main() {
  M3uEntry live(String url, {String? group}) => M3uEntry(
      kind: M3uEntryKind.live, name: 'Ch', url: url, groupTitle: group);
  M3uEntry movie(String url) => M3uEntry(
      kind: M3uEntryKind.movie,
      name: 'Dune',
      url: url,
      groupTitle: 'Movies',
      containerExtension: 'mkv');
  M3uEntry ep(String url, int number) => M3uEntry(
      kind: M3uEntryKind.episode,
      name: 'Dark S01E0$number',
      url: url,
      groupTitle: 'Shows',
      seriesName: 'Dark',
      seasonNumber: 1,
      episodeNumber: number,
      containerExtension: 'mp4');

  test('maps live/movie entries to rows carrying their absolute url', () {
    final catalog = M3uCatalogBuilder.build(
      'acct',
      M3uPlaylist(entries: [
        live('http://h/live/1.ts', group: 'News'),
        movie('http://h/movie/9.mkv'),
      ]),
    );

    expect(catalog.live, hasLength(1));
    expect(catalog.live.single.type, ContentType.live);
    expect(catalog.live.single.categoryId, 'News');
    expect(catalog.live.single.extra['url'], 'http://h/live/1.ts');

    expect(catalog.movies.single.extra['url'], 'http://h/movie/9.mkv');
    expect(catalog.movies.single.extra['containerExtension'], 'mkv');
  });

  test('groups episodes of one series into a single series row', () {
    final catalog = M3uCatalogBuilder.build(
      'acct',
      M3uPlaylist(entries: [
        ep('http://h/series/1.mp4', 1),
        ep('http://h/series/2.mp4', 2),
      ]),
    );

    expect(catalog.series, hasLength(1));
    final row = catalog.series.single;
    expect(row.name, 'Dark');
    expect(row.categoryId, 'Shows');
    final episodes = row.extra['episodes'] as List;
    expect(episodes, hasLength(2));
    expect(episodes.first['url'], 'http://h/series/1.mp4');
  });

  test('ids are stable across builds (keyed on the stream url)', () {
    final a = M3uCatalogBuilder.build(
        'acct', M3uPlaylist(entries: [live('http://h/live/1.ts')]));
    final b = M3uCatalogBuilder.build(
        'acct', M3uPlaylist(entries: [live('http://h/live/1.ts')]));
    expect(a.live.single.id, b.live.single.id);
    expect(a.live.single.id, M3uCatalogBuilder.idFor('http://h/live/1.ts'));
  });

  test('a missing group-title falls back to Uncategorized', () {
    final catalog = M3uCatalogBuilder.build(
        'acct', M3uPlaylist(entries: [live('http://h/live/1.ts')]));
    expect(catalog.live.single.categoryId, M3uCatalogBuilder.uncategorized);
  });

  test('maps #EXTVLCOPT options to HTTP headers on the live row', () {
    const entry = M3uEntry(
      kind: M3uEntryKind.live,
      name: 'Ch',
      url: 'http://h/live/1.ts',
      groupTitle: 'News',
      vlcOpts: {
        'http-user-agent': 'MyAgent/1.0',
        'http-referrer': 'http://ref',
      },
    );
    final catalog =
        M3uCatalogBuilder.build('acct', const M3uPlaylist(entries: [entry]));
    expect(catalog.live.single.extra['headers'],
        {'User-Agent': 'MyAgent/1.0', 'Referer': 'http://ref'});
  });

  test('omits headers when the entry declares no #EXTVLCOPT', () {
    final catalog = M3uCatalogBuilder.build(
        'acct', M3uPlaylist(entries: [live('http://h/live/1.ts')]));
    expect(catalog.live.single.extra.containsKey('headers'), isFalse);
  });
}
