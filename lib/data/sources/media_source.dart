import '../models/account.dart';
import '../models/account_status.dart';
import '../models/category.dart';
import '../models/channel.dart';
import '../models/epg_program.dart';
import '../models/movie.dart';
import '../models/movie_info.dart';
import '../models/series_info.dart';
import '../models/series_item.dart';
import 'm3u_media_source.dart';
import 'xtream_media_source.dart';

/// The default retry budget for interactive source calls (someone is watching a
/// spinner). Mirrors the Xtream service's own default so behavior is unchanged
/// when routing through a source.
const int kInteractiveMaxRetries = 2;

/// A per-account data source: the seam that lets the whole UI browse, play, and
/// show EPG without knowing whether the playlist is an Xtream panel or a flat
/// M3U file. Bound to one [account]; the concrete implementation is chosen by
/// [MediaSource.forAccount].
///
/// Method names/shapes deliberately mirror the original `XtreamApiService` so
/// the Phase-0 refactor is a mechanical "call the source instead of the API"
/// with no behavior change for Xtream accounts.
abstract class MediaSource {
  /// The playlist this source serves.
  Account get account;

  /// Picks the right implementation for [account]'s [Account.sourceKind].
  factory MediaSource.forAccount(Account account) {
    switch (account.sourceKind) {
      case AccountSourceKind.xtream:
        return XtreamMediaSource(account);
      case AccountSourceKind.m3u:
        return M3uMediaSource(account);
    }
  }

  /// True when [getAccountStatus] returns real data (Xtream). M3U has no
  /// subscription/expiry concept, so the UI hides the account-status card.
  bool get supportsAccountStatus;

  /// Validates the playlist is reachable/usable; throws on failure. Called once
  /// when adding a playlist.
  Future<void> validate();

  /// The account's subscription/connection status. Only meaningful when
  /// [supportsAccountStatus] is true.
  Future<AccountStatus> getAccountStatus(
      {int maxRetries = kInteractiveMaxRetries});

  // ---- Live ----
  Future<List<Category>> getLiveCategories(
      {int maxRetries = kInteractiveMaxRetries});
  Future<List<Channel>> getLiveStreams(String categoryId,
      {int maxRetries = kInteractiveMaxRetries});
  Future<List<EpgProgram>> getShortEpg(String streamId);
  Future<List<EpgProgram>> getSimpleDataTable(String streamId);

  // ---- Movies (VOD) ----
  Future<List<Category>> getVodCategories(
      {int maxRetries = kInteractiveMaxRetries});
  Future<List<Movie>> getVodStreams(String categoryId,
      {int maxRetries = kInteractiveMaxRetries});
  Future<MovieInfo> getVodInfo(String streamId,
      {int maxRetries = kInteractiveMaxRetries});

  // ---- Series ----
  Future<List<Category>> getSeriesCategories(
      {int maxRetries = kInteractiveMaxRetries});
  Future<List<SeriesItem>> getSeries(String categoryId,
      {int maxRetries = kInteractiveMaxRetries});
  Future<SeriesInfo> getSeriesInfo(String seriesId,
      {int maxRetries = kInteractiveMaxRetries});

  // ---- Playable URL resolution ----
  // For Xtream these build the `{server}/{live|movie|series}/{user}/{pass}/…`
  // path; for M3U they return the entry's absolute URL verbatim.
  String liveUrl(Channel channel);

  /// Re-hydrates a [channel] that was reconstructed from a denormalized
  /// snapshot (Favorites, Home rails, Watch History) into a playable one.
  /// Xtream builds URLs from the stream id alone, so this is the identity;
  /// M3U carries the URL (and any `#EXTVLCOPT` headers) on the model, so a
  /// snapshot-rebuilt channel must be re-read from the offline catalog first
  /// or [liveUrl] comes back empty.
  Future<Channel> resolveChannel(Channel channel);
  String vodUrl(Movie movie);
  String episodeUrl(Episode episode);

  // ---- Catch-up / timeshift ----

  /// Whether [channel] can replay past programmes (Xtream `tv_archive`).
  /// Always false for M3U.
  bool supportsCatchup(Channel channel);

  /// The stream URL replaying [channel] from [start] for [duration], or null
  /// when the source has no timeshift support. [start] is the panel's own
  /// EPG-local time (the same clock its guide timestamps use).
  String? timeshiftUrl(Channel channel, DateTime start, Duration duration);
}
