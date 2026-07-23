import '../api/xtream_api_service.dart';
import '../models/account.dart';
import '../models/account_status.dart';
import '../models/category.dart';
import '../models/channel.dart';
import '../models/epg_program.dart';
import '../models/movie.dart';
import '../models/movie_info.dart';
import '../models/series_info.dart';
import '../models/series_item.dart';
import 'media_source.dart';

/// [MediaSource] backed by an Xtream Codes panel — a thin adapter over the
/// existing [XtreamApiService] that binds the account and preserves the exact
/// previous behavior (same endpoints, caching, retries, and URL formats).
class XtreamMediaSource implements MediaSource {
  @override
  final Account account;

  final XtreamApiService _api;

  XtreamMediaSource(this.account, {XtreamApiService? api})
      : _api = api ?? XtreamApiService();

  @override
  bool get supportsAccountStatus => true;

  @override
  Future<void> validate() => _api.authenticate(account);

  @override
  Future<AccountStatus> getAccountStatus(
          {int maxRetries = kInteractiveMaxRetries}) =>
      _api.getAccountStatus(account, maxRetries: maxRetries);

  @override
  Future<List<Category>> getLiveCategories(
          {int maxRetries = kInteractiveMaxRetries}) =>
      _api.getLiveCategories(account, maxRetries: maxRetries);

  @override
  Future<List<Channel>> getLiveStreams(String categoryId,
          {int maxRetries = kInteractiveMaxRetries}) =>
      _api.getLiveStreams(account, categoryId, maxRetries: maxRetries);

  @override
  Future<List<EpgProgram>> getShortEpg(String streamId) =>
      _api.getShortEpg(account, streamId);

  @override
  Future<List<EpgProgram>> getSimpleDataTable(String streamId) =>
      _api.getSimpleDataTable(account, streamId);

  @override
  Future<List<Category>> getVodCategories(
          {int maxRetries = kInteractiveMaxRetries}) =>
      _api.getVodCategories(account, maxRetries: maxRetries);

  @override
  Future<List<Movie>> getVodStreams(String categoryId,
          {int maxRetries = kInteractiveMaxRetries}) =>
      _api.getVodStreams(account, categoryId, maxRetries: maxRetries);

  @override
  Future<MovieInfo> getVodInfo(String streamId,
          {int maxRetries = kInteractiveMaxRetries}) =>
      _api.getVodInfo(account, streamId, maxRetries: maxRetries);

  @override
  Future<List<Category>> getSeriesCategories(
          {int maxRetries = kInteractiveMaxRetries}) =>
      _api.getSeriesCategories(account, maxRetries: maxRetries);

  @override
  Future<List<SeriesItem>> getSeries(String categoryId,
          {int maxRetries = kInteractiveMaxRetries}) =>
      _api.getSeries(account, categoryId, maxRetries: maxRetries);

  @override
  Future<SeriesInfo> getSeriesInfo(String seriesId,
          {int maxRetries = kInteractiveMaxRetries}) =>
      _api.getSeriesInfo(account, seriesId, maxRetries: maxRetries);

  @override
  String liveUrl(Channel channel) => channel.streamUrl(
        serverUrl: account.serverUrl,
        username: account.username,
        password: account.password,
      );

  // Xtream URLs are built from the stream id alone — a snapshot-rebuilt
  // channel is already playable as-is.
  @override
  Future<Channel> resolveChannel(Channel channel) async => channel;

  @override
  String vodUrl(Movie movie) => movie.streamUrl(
        serverUrl: account.serverUrl,
        username: account.username,
        password: account.password,
      );

  @override
  String episodeUrl(Episode episode) => episode.streamUrl(
        serverUrl: account.serverUrl,
        username: account.username,
        password: account.password,
      );

  @override
  bool supportsCatchup(Channel channel) => channel.tvArchive;

  /// Xtream's timeshift endpoint:
  /// `{server}/timeshift/{user}/{pass}/{minutes}/{YYYY-MM-DD:HH-MM}/{id}.ts`.
  /// The start goes in as the panel's guide-local wall time — the same values
  /// its EPG handed us — so no timezone conversion is applied here.
  @override
  String? timeshiftUrl(Channel channel, DateTime start, Duration duration) {
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp = '${start.year}-${two(start.month)}-${two(start.day)}'
        ':${two(start.hour)}-${two(start.minute)}';
    final minutes = duration.inMinutes.clamp(1, 24 * 60);
    return '${account.serverUrl}/timeshift/${account.username}/'
        '${account.password}/$minutes/$stamp/${channel.streamId}.ts';
  }
}
