import 'dart:io';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../db/catalog_database.dart';
import '../models/account.dart';
import '../models/account_status.dart';
import '../models/catalog_row.dart';
import '../models/category.dart';
import '../models/channel.dart';
import '../models/epg_program.dart';
import '../models/movie.dart';
import '../models/movie_info.dart';
import '../models/search_result.dart';
import '../models/series_info.dart';
import '../models/series_item.dart';
import 'm3u_catalog_builder.dart';
import 'm3u_parser.dart';
import 'media_source.dart';
import 'xmltv_parser.dart';

/// Fetches a playlist's raw text. Injectable so tests supply a fake without
/// touching the network.
typedef PlaylistFetcher = Future<String> Function(String url);

/// Thrown when an M3U playlist can't be loaded or has no usable entries.
class M3uException implements Exception {
  final String message;
  M3uException(this.message);
  @override
  String toString() => message;
}

/// [MediaSource] backed by a flat M3U/M3U8 playlist. Unlike Xtream there's no
/// live API: [refresh] fetches + parses the playlist into the offline catalog
/// (via [M3uCatalogBuilder]) and every browse call reads back from there. URLs
/// are the entries' own absolute URLs, carried on the model, so the `*Url`
/// methods just return them.
class M3uMediaSource implements MediaSource {
  @override
  final Account account;

  final PlaylistFetcher _fetch;
  final CatalogDatabase _db;

  M3uMediaSource(this.account, {PlaylistFetcher? fetch, CatalogDatabase? db})
      : _fetch = fetch ?? _dioFetch,
        _db = db ?? CatalogDatabase.instance;

  /// Fetches a playlist/EPG source that may be a URL *or* a local file:
  /// http/https go over the network; a `file://` URI or a bare filesystem
  /// path (including Windows `C:\...`, whose drive letter would otherwise
  /// parse as a URI scheme) is read from disk.
  static Future<String> _dioFetch(String url) async {
    final uri = Uri.tryParse(url);
    final scheme = uri?.scheme.toLowerCase() ?? '';
    if (scheme == 'http' || scheme == 'https') {
      // Bounded like XtreamApiService's calls — a hung playlist/EPG server
      // must not stall the refresh forever. receiveTimeout is between-chunk
      // (not whole-body), so a large-but-flowing XMLTV file still downloads.
      final res = await Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30),
      )).get<String>(
        url,
        options: Options(responseType: ResponseType.plain),
      );
      return res.data ?? '';
    }
    final file = scheme == 'file' ? File.fromUri(uri!) : File(url);
    return file.readAsString();
  }

  @override
  bool get supportsAccountStatus => false;

  @override
  Future<void> validate() async {
    final playlist = M3uParser.parse(await _fetch(account.m3uUrl ?? ''));
    if (playlist.isEmpty) {
      throw M3uException('No channels found in this playlist.');
    }
  }

  /// Fetches the playlist and rewrites this account's catalog from it. This is
  /// the M3U equivalent of Xtream's background catalog sync. Also refreshes the
  /// XMLTV EPG (best-effort — an EPG failure never fails the catalog).
  Future<void> refresh() async {
    final playlist = M3uParser.parse(await _fetch(account.m3uUrl ?? ''));
    final catalog = M3uCatalogBuilder.build(account.key, playlist);
    await _db.replaceTypeItems(account.key, ContentType.live, catalog.live);
    await _db.replaceTypeItems(account.key, ContentType.movie, catalog.movies);
    await _db.replaceTypeItems(account.key, ContentType.series, catalog.series);
    final now = DateTime.now();
    for (final type in ContentType.values) {
      await _db.setTypeSyncedAt(account.key, type, now);
    }
    // Prefer the account's explicit EPG URL, falling back to the playlist's
    // own `url-tvg` declaration. Refreshed on its own (longer) cadence — an
    // XMLTV feed is large and changes far less often than the playlist, so it
    // shouldn't be refetched on every 15-minute catalog sync.
    final epgUrl = _nonEmpty(account.epgUrl) ?? _nonEmpty(playlist.epgUrl);
    if (epgUrl != null && await _epgIsStale()) await _refreshEpg(epgUrl);
  }

  /// How long a stored XMLTV guide is trusted before it's refetched.
  static const _epgRefreshInterval = Duration(hours: 6);
  static String _epgSyncedKey(String accountKey) =>
      'm3u_epg_synced_v1_$accountKey';

  Future<bool> _epgIsStale() async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt(_epgSyncedKey(account.key));
    if (last == null) return true;
    final age = DateTime.now().millisecondsSinceEpoch - last;
    return age >= _epgRefreshInterval.inMilliseconds;
  }

  Future<void> _refreshEpg(String url) async {
    try {
      final programmes = XmltvParser.parse(await _fetch(url));
      await _db.replaceXmltv(account.key, programmes);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
          _epgSyncedKey(account.key), DateTime.now().millisecondsSinceEpoch);
    } catch (_) {
      // EPG is a bonus; a bad/unreachable feed shouldn't fail the refresh.
    }
  }

  static String? _nonEmpty(String? v) =>
      (v != null && v.trim().isNotEmpty) ? v.trim() : null;

  @override
  Future<AccountStatus> getAccountStatus(
          {int maxRetries = kInteractiveMaxRetries}) =>
      throw UnsupportedError('M3U playlists have no account status');

  // ---- Live ----
  @override
  Future<List<Category>> getLiveCategories(
          {int maxRetries = kInteractiveMaxRetries}) =>
      _categories(ContentType.live);

  @override
  Future<List<Channel>> getLiveStreams(String categoryId,
      {int maxRetries = kInteractiveMaxRetries}) async {
    final rows = await _rowsIn(ContentType.live, categoryId);
    return [
      for (final r in rows)
        Channel(
          streamId: r.id,
          name: r.name,
          categoryId: r.categoryId,
          logoUrl: r.imageUrl,
          url: r.extra['url'] as String?,
          headers: castHeaders(r.extra['headers']),
        ),
    ];
  }

  @override
  Future<List<EpgProgram>> getShortEpg(String streamId) async {
    final channelId = await _tvgIdFor(streamId);
    if (channelId == null) return const [];
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = await _db.epgProgrammes(
      account.key,
      channelId,
      fromMs: now,
      toMs: now + const Duration(days: 1).inMilliseconds,
      limit: 6, // now + the next few, for the now/next strip
    );
    return rows.map(_toEpgProgram).toList();
  }

  @override
  Future<List<EpgProgram>> getSimpleDataTable(String streamId) async {
    final channelId = await _tvgIdFor(streamId);
    if (channelId == null) return const [];
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = await _db.epgProgrammes(
      account.key,
      channelId,
      fromMs: now - const Duration(hours: 6).inMilliseconds,
      toMs: now + const Duration(days: 2).inMilliseconds,
    );
    return rows.map(_toEpgProgram).toList();
  }

  /// A channel's `tvg-id` (kept in its catalog row's extra), for EPG matching.
  Future<String?> _tvgIdFor(String streamId) async {
    final row = await _db.itemById(account.key, ContentType.live, streamId);
    return row?.extra['tvgId'] as String?;
  }

  static EpgProgram _toEpgProgram(Map<String, Object?> row) => EpgProgram(
        title: row['title'] as String? ?? '',
        description: row['description'] as String? ?? '',
        start: DateTime.fromMillisecondsSinceEpoch(row['start_ms'] as int),
        end: DateTime.fromMillisecondsSinceEpoch(row['stop_ms'] as int),
      );

  // ---- Movies ----
  @override
  Future<List<Category>> getVodCategories(
          {int maxRetries = kInteractiveMaxRetries}) =>
      _categories(ContentType.movie);

  @override
  Future<List<Movie>> getVodStreams(String categoryId,
      {int maxRetries = kInteractiveMaxRetries}) async {
    final rows = await _rowsIn(ContentType.movie, categoryId);
    return [
      for (final r in rows)
        Movie(
          streamId: r.id,
          name: r.name,
          categoryId: r.categoryId,
          containerExtension: r.extra['containerExtension'] as String? ?? 'mp4',
          posterUrl: r.imageUrl,
          url: r.extra['url'] as String?,
        ),
    ];
  }

  @override
  Future<MovieInfo> getVodInfo(String streamId,
          {int maxRetries = kInteractiveMaxRetries}) async =>
      // M3U carries no detail; the tile data (from the list) is all there is.
      const MovieInfo();

  // ---- Series ----
  @override
  Future<List<Category>> getSeriesCategories(
          {int maxRetries = kInteractiveMaxRetries}) =>
      _categories(ContentType.series);

  @override
  Future<List<SeriesItem>> getSeries(String categoryId,
      {int maxRetries = kInteractiveMaxRetries}) async {
    final rows = await _rowsIn(ContentType.series, categoryId);
    return [
      for (final r in rows)
        SeriesItem(
          seriesId: r.id,
          name: r.name,
          categoryId: r.categoryId,
          coverUrl: r.imageUrl,
        ),
    ];
  }

  @override
  Future<SeriesInfo> getSeriesInfo(String seriesId,
      {int maxRetries = kInteractiveMaxRetries}) async {
    final row =
        await _db.itemById(account.key, ContentType.series, seriesId);
    if (row == null) return const SeriesInfo(seasons: []);

    final rawEpisodes = (row.extra['episodes'] as List?) ?? const [];
    final bySeason = <int, List<Episode>>{};
    for (final raw in rawEpisodes) {
      final m = (raw as Map).cast<String, dynamic>();
      final season = (m['season'] as num?)?.toInt() ?? 1;
      bySeason.putIfAbsent(season, () => []).add(Episode(
            id: m['id'] as String,
            title: m['title'] as String? ?? 'Episode',
            episodeNum: (m['episode'] as num?)?.toInt() ?? 0,
            containerExtension: m['container'] as String? ?? 'mp4',
            url: m['url'] as String?,
          ));
    }
    final seasons = bySeason.entries.map((e) {
      e.value.sort((a, b) => a.episodeNum.compareTo(b.episodeNum));
      return Season(
        seasonNumber: e.key,
        name: 'Season ${e.key}',
        episodes: e.value,
      );
    }).toList()
      ..sort((a, b) => a.seasonNumber.compareTo(b.seasonNumber));
    return SeriesInfo(seasons: seasons, coverUrl: row.imageUrl);
  }

  // ---- URL resolution — the entry's own absolute URL, carried on the model.
  // Null-safe: a model reconstructed without its URL (an unusual path) yields an
  // empty string the player reports as an error, rather than crashing. ----
  @override
  String liveUrl(Channel channel) => channel.url ?? '';

  @override
  Future<Channel> resolveChannel(Channel channel) async {
    if (channel.url != null) return channel; // already playable
    final row =
        await _db.itemById(account.key, ContentType.live, channel.streamId);
    if (row == null) return channel; // gone from the playlist — empty-URL error
    return Channel(
      streamId: channel.streamId,
      name: channel.name.isNotEmpty ? channel.name : row.name,
      categoryId:
          channel.categoryId.isNotEmpty ? channel.categoryId : row.categoryId,
      logoUrl: channel.logoUrl ?? row.imageUrl,
      url: row.extra['url'] as String?,
      headers: castHeaders(row.extra['headers']),
    );
  }

  @override
  String vodUrl(Movie movie) => movie.url ?? '';

  @override
  String episodeUrl(Episode episode) => episode.url ?? '';

  // M3U entries carry a plain URL with no archive endpoint to build from.
  @override
  bool supportsCatchup(Channel channel) => false;

  @override
  String? timeshiftUrl(Channel channel, DateTime start, Duration duration) =>
      null;

  /// Distinct categories for [type], as `Category(id == name)` (M3U's category
  /// is just the group-title string), sorted case-insensitively. Resolved in
  /// SQL — a big playlist would make loading the whole type into Dart jank on
  /// every category tap.
  Future<List<Category>> _categories(ContentType type) async {
    final ids = await _db.categoryIdsForType(account.key, type);
    return [
      for (final name in ids) Category(categoryId: name, categoryName: name),
    ];
  }

  Future<List<CatalogRow>> _rowsIn(ContentType type, String categoryId) =>
      _db.itemsInCategory(account.key, type, categoryId);
}
