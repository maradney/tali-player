import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/models/download_item.dart';

void main() {
  DownloadItem movie() => const DownloadItem(
        type: 'movie',
        id: '120',
        name: 'The Matrix',
        categoryId: '4',
        containerExtension: 'mkv',
        remoteUrl: 'http://host/movie/u/p/120.mkv',
        status: DownloadStatus.completed,
        addedAt: 111,
        posterUrl: 'http://host/p.jpg',
      );

  DownloadItem episode() => const DownloadItem(
        type: 'episode',
        id: 'e9',
        name: 'Pilot',
        seriesName: 'Dark',
        seriesId: 's1',
        seasonNumber: 1,
        episodeNum: 1,
        categoryId: '5',
        containerExtension: 'mp4',
        remoteUrl: 'http://host/series/u/p/e9.mp4',
        status: DownloadStatus.queued,
        addedAt: 222,
      );

  test('fileName is type_id.ext', () {
    expect(movie().fileName, 'movie_120.mkv');
    expect(episode().fileName, 'episode_e9.mp4');
  });

  test('playbackRef carries the resume fields', () {
    final ref = episode().playbackRef;
    expect(ref.type, 'episode');
    expect(ref.id, 'e9');
    expect(ref.seriesId, 's1');
    expect(ref.seasonNumber, 1);
    expect(ref.episodeNum, 1);
    expect(ref.categoryId, '5');
  });

  test('JSON round-trips both types', () {
    for (final item in [movie(), episode()]) {
      final back = DownloadItem.fromJson(item.toJson());
      expect(back.toJson(), item.toJson());
    }
  });

  test('copyWith changes only status', () {
    final m = movie();
    final f = m.copyWith(status: DownloadStatus.failed);
    expect(f.status, DownloadStatus.failed);
    expect(f.id, m.id);
    expect(f.remoteUrl, m.remoteUrl);
  });

  test('toFavoriteItem maps an episode to its parent series', () {
    final fav = episode().toFavoriteItem();
    expect(fav.type, 'series');
    expect(fav.id, 's1'); // the seriesId, not the episode id
    expect(fav.name, 'Dark'); // the series name, not the episode title
    expect(fav.categoryId, '5');
    expect(fav.extra, isEmpty); // containerExtension is a movie-only extra
  });

  test('toFavoriteItem maps a movie to itself with its container', () {
    final fav = movie().toFavoriteItem();
    expect(fav.type, 'movie');
    expect(fav.id, '120');
    expect(fav.imageUrl, 'http://host/p.jpg');
    expect(fav.extra['containerExtension'], 'mkv');
  });

  test('headers persist through JSON and survive copyWith', () {
    const withHeaders = DownloadItem(
      type: 'movie',
      id: '7',
      name: 'UA Movie',
      categoryId: '1',
      containerExtension: 'mp4',
      remoteUrl: 'http://host/7.mp4',
      headers: {'User-Agent': 'Mozilla/5.0'},
      status: DownloadStatus.queued,
      addedAt: 1,
    );
    final back = DownloadItem.fromJson(withHeaders.toJson());
    expect(back.headers, {'User-Agent': 'Mozilla/5.0'});
    expect(back.copyWith(status: DownloadStatus.failed).headers,
        {'User-Agent': 'Mozilla/5.0'});
    // Absent headers stay null (Xtream), including for pre-headers records.
    expect(DownloadItem.fromJson(movie().toJson()).headers, isNull);
  });

  test('an unknown status decodes to failed rather than throwing', () {
    final json = movie().toJson()..['status'] = 'bogus';
    expect(DownloadItem.fromJson(json).status, DownloadStatus.failed);
  });
}
