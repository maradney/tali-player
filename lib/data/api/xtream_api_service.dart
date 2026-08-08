import 'package:dio/dio.dart';
// `show` needed: a bare foundation import drags in its `Category` annotation,
// which clashes with our Category model everywhere this file is imported.
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../db/catalog_database.dart';
import '../models/account.dart';
import '../models/account_status.dart';
import '../models/category.dart';
import '../models/channel.dart';
import '../models/epg_program.dart';
import '../models/movie.dart';
import '../models/movie_info.dart';
import '../models/series_item.dart';
import '../models/series_info.dart';
import '../services/diagnostics_log.dart';
import 'credential_redaction.dart';
import 'tls_failure.dart';

/// How long a cached movie/series detail response (plot/cast/genre/
/// seasons) is trusted before it's treated as stale and re-fetched.
const _detailCacheMaxAge = Duration(days: 7);

/// How long a cached get_short_epg response is trusted. Short because it's
/// "now/next" - a program can end and the next one start within this
/// window, so it can't be cached as long as detail data.
const _shortEpgCacheMaxAge = Duration(minutes: 10);

/// How long a cached get_simple_data_table response is trusted.
const _fullEpgCacheMaxAge = Duration(minutes: 15);

/// Default retry budget for interactive calls - someone tapped something
/// and is watching a spinner, so fail fast to the error/retry UI rather
/// than silently waiting out a minute of 429 backoff.
const _interactiveMaxRetries = 2;

/// Machine-readable categories for [XtreamApiException], so the UI can show
/// a localized message (this layer has no BuildContext — the English
/// [XtreamApiException.message] is a diagnostics/fallback string, not what
/// the user should see). Mapped to l10n in `describeApiError`.
enum XtreamApiErrorKind {
  invalidCredentials,

  /// https:// against a port that only speaks plain HTTP - the usual mistake
  /// with Xtream panels, which serve http:// on 8080. Kept separate from
  /// [tlsHandshakeFailed] because the fix is one word in the URL.
  httpsNotSupported,

  /// TLS was attempted and failed for another reason (expired, self-signed or
  /// mismatched certificate). Nothing the user can fix by editing the URL.
  tlsHandshakeFailed,

  notXtreamPanel,
  badResponse,
  timeout,
  unreachable,
  rateLimited,
  unavailable,
  other,
}

/// Thrown for any Xtream API failure - bad credentials, unreachable
/// server, malformed response, etc. The UI layer catches this and
/// shows a message instead of a raw stack trace.
class XtreamApiException implements Exception {
  final String message;

  /// What went wrong, for localized display; [message] is the English detail.
  final XtreamApiErrorKind kind;

  /// True for a 429 response that survived all retries. Lets callers
  /// recognize this specific case - e.g. to explain that it's likely the
  /// background catalog sync competing for requests, not a real outage.
  final bool isRateLimited;

  XtreamApiException(
    this.message, {
    this.isRateLimited = false,
    this.kind = XtreamApiErrorKind.other,
  });

  @override
  String toString() => message;
}

class XtreamApiService {
  /// Retry budget for background work (the catalog sync) - nobody is
  /// watching a spinner, so it can afford to wait out longer 429 backoffs
  /// instead of giving up and leaving the index incomplete.
  static const backgroundMaxRetries = 5;

  final Dio _dio;

  XtreamApiService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
            ));

  /// Validates credentials and returns basic account info from the panel.
  /// Call this first, before any category/stream calls, so the user gets
  /// a clear "wrong login" error instead of a confusing empty list later.
  Future<Map<String, dynamic>> authenticate(Account account) async {
    final response = await _get(account.apiBaseUrl);

    // A working Xtream login returns a JSON object with a "user_info" key.
    // A bad login (or a URL that isn't an Xtream panel at all) returns
    // something else - HTML, an error object, or an empty body.
    if (response is Map<String, dynamic> && response.containsKey('user_info')) {
      final userInfo = response['user_info'] as Map<String, dynamic>;
      if (userInfo['auth'] == 0) {
        throw XtreamApiException('Invalid username or password.',
            kind: XtreamApiErrorKind.invalidCredentials);
      }
      return userInfo;
    }

    throw XtreamApiException(
      'Unexpected response from server. Check the server URL is correct '
      'and points to an Xtream panel.',
      kind: XtreamApiErrorKind.notXtreamPanel,
    );
  }

  /// Fetches the account's own subscription/connection status from the base
  /// player_api.php response (the `user_info` block). Unlike [authenticate],
  /// this does not throw for an expired/disabled account - a lapsed status is
  /// exactly the information the caller wants to show.
  Future<AccountStatus> getAccountStatus(
    Account account, {
    int maxRetries = _interactiveMaxRetries,
  }) async {
    final response = await _get(account.apiBaseUrl, maxRetries: maxRetries);
    if (response is Map<String, dynamic> && response['user_info'] is Map) {
      return AccountStatus.fromUserInfoJson(
        (response['user_info'] as Map).cast<String, dynamic>(),
      );
    }
    throw XtreamApiException(
      'Could not read account status from the server.',
      kind: XtreamApiErrorKind.badResponse,
    );
  }

  Future<List<Category>> getLiveCategories(
    Account account, {
    int maxRetries = _interactiveMaxRetries,
  }) async {
    final url = '${account.apiBaseUrl}&action=get_live_categories';
    final response = await _get(url, maxRetries: maxRetries);

    if (response is! List) {
      throw XtreamApiException('Unexpected category response format.',
          kind: XtreamApiErrorKind.badResponse);
    }

    return response
        .cast<Map<String, dynamic>>()
        .map(Category.fromJson)
        .toList();
  }

  Future<List<Channel>> getLiveStreams(
    Account account,
    String categoryId, {
    int maxRetries = _interactiveMaxRetries,
  }) async {
    final url =
        '${account.apiBaseUrl}&action=get_live_streams&category_id=$categoryId';
    final response = await _get(url, maxRetries: maxRetries);

    if (response is! List) {
      throw XtreamApiException('Unexpected channel response format.',
          kind: XtreamApiErrorKind.badResponse);
    }

    return response
        .cast<Map<String, dynamic>>()
        .map(Channel.fromJson)
        .toList();
  }

  /// Returns the current + upcoming programs for a channel. Not every
  /// channel has EPG data - an empty list is a normal, expected result,
  /// not an error, so this never throws for "no data".
  ///
  /// Cached on disk briefly ([_shortEpgCacheMaxAge]) - short because "now"
  /// changes as programs end, unlike movie/series detail which barely
  /// changes at all. Still saves a round trip for the common case of
  /// reopening the same channel or scrolling past it again within a
  /// few minutes.
  Future<List<EpgProgram>> getShortEpg(Account account, String streamId) async {
    final cached = await CatalogDatabase.instance.getCachedEpg(
      account.key,
      streamId,
      'short',
      maxAge: _shortEpgCacheMaxAge,
    );
    if (cached != null) return cached.map(EpgProgram.fromJson).toList();

    final url = '${account.apiBaseUrl}&action=get_short_epg&stream_id=$streamId';
    final response = await _get(url);

    if (response is! Map<String, dynamic>) return [];
    final listings = response['epg_listings'];
    if (listings is! List) return [];
    final rawListings = listings.cast<Map<String, dynamic>>();

    final programs = <EpgProgram>[];
    for (final item in rawListings) {
      try {
        programs.add(EpgProgram.fromJson(item));
      } catch (_) {
        // Skip any malformed entry rather than failing the whole list -
        // panels are inconsistent about EPG data quality.
        continue;
      }
    }
    await CatalogDatabase.instance
        .saveEpg(account.key, streamId, 'short', rawListings);
    return programs;
  }

  /// Fuller EPG listing for a channel than [getShortEpg] - covers roughly
  /// a day rather than just the next handful of programs, which is what
  /// the grid guide needs to fill a multi-hour timeline instead of just
  /// "now" and "next". Cached longer ([_fullEpgCacheMaxAge]) since the
  /// grid opens one of these per visible channel at once - without a
  /// cache, reopening or resizing the window re-fetches the whole
  /// day's schedule for every channel again.
  Future<List<EpgProgram>> getSimpleDataTable(
    Account account,
    String streamId,
  ) async {
    final cached = await CatalogDatabase.instance.getCachedEpg(
      account.key,
      streamId,
      'full',
      maxAge: _fullEpgCacheMaxAge,
    );
    if (cached != null) return cached.map(EpgProgram.fromJson).toList();

    final url =
        '${account.apiBaseUrl}&action=get_simple_data_table&stream_id=$streamId';
    final response = await _get(url);

    if (response is! Map<String, dynamic>) return [];
    final listings = response['epg_listings'];
    if (listings is! List) return [];
    final rawListings = listings.cast<Map<String, dynamic>>();

    final programs = <EpgProgram>[];
    for (final item in rawListings) {
      try {
        programs.add(EpgProgram.fromJson(item));
      } catch (_) {
        continue;
      }
    }
    await CatalogDatabase.instance
        .saveEpg(account.key, streamId, 'full', rawListings);
    return programs;
  }

  // ---- Movies (VOD) ----

  Future<List<Category>> getVodCategories(
    Account account, {
    int maxRetries = _interactiveMaxRetries,
  }) async {
    final url = '${account.apiBaseUrl}&action=get_vod_categories';
    final response = await _get(url, maxRetries: maxRetries);

    if (response is! List) {
      throw XtreamApiException('Unexpected category response format.',
          kind: XtreamApiErrorKind.badResponse);
    }
    return response.cast<Map<String, dynamic>>().map(Category.fromJson).toList();
  }

  Future<List<Movie>> getVodStreams(
    Account account,
    String categoryId, {
    int maxRetries = _interactiveMaxRetries,
  }) async {
    final url =
        '${account.apiBaseUrl}&action=get_vod_streams&category_id=$categoryId';
    final response = await _get(url, maxRetries: maxRetries);

    if (response is! List) {
      throw XtreamApiException('Unexpected movie response format.',
          kind: XtreamApiErrorKind.badResponse);
    }
    return response.cast<Map<String, dynamic>>().map(Movie.fromJson).toList();
  }

  /// Fetches overview detail (plot/cast/director/genre) for one movie -
  /// only called once the user drills into a specific movie. Cached on
  /// disk since this content rarely changes, so reopening a movie you've
  /// already viewed skips the network round trip entirely.
  Future<MovieInfo> getVodInfo(
    Account account,
    String streamId, {
    int maxRetries = _interactiveMaxRetries,
  }) async {
    final cached = await CatalogDatabase.instance.getCachedDetail(
      account.key,
      'movie',
      streamId,
      maxAge: _detailCacheMaxAge,
    );
    if (cached != null) return MovieInfo.fromJson(cached);

    final url = '${account.apiBaseUrl}&action=get_vod_info&vod_id=$streamId';
    final response = await _get(url, maxRetries: maxRetries);

    if (response is! Map<String, dynamic>) {
      throw XtreamApiException('Unexpected movie detail response format.',
          kind: XtreamApiErrorKind.badResponse);
    }
    await CatalogDatabase.instance.saveDetail(account.key, 'movie', streamId, response);
    return MovieInfo.fromJson(response);
  }

  // ---- Series ----

  Future<List<Category>> getSeriesCategories(
    Account account, {
    int maxRetries = _interactiveMaxRetries,
  }) async {
    final url = '${account.apiBaseUrl}&action=get_series_categories';
    final response = await _get(url, maxRetries: maxRetries);

    if (response is! List) {
      throw XtreamApiException('Unexpected category response format.',
          kind: XtreamApiErrorKind.badResponse);
    }
    return response.cast<Map<String, dynamic>>().map(Category.fromJson).toList();
  }

  Future<List<SeriesItem>> getSeries(
    Account account,
    String categoryId, {
    int maxRetries = _interactiveMaxRetries,
  }) async {
    final url =
        '${account.apiBaseUrl}&action=get_series&category_id=$categoryId';
    final response = await _get(url, maxRetries: maxRetries);

    if (response is! List) {
      throw XtreamApiException('Unexpected series response format.',
          kind: XtreamApiErrorKind.badResponse);
    }
    return response.cast<Map<String, dynamic>>().map(SeriesItem.fromJson).toList();
  }

  /// Fetches full season/episode detail for one series - only called
  /// once the user drills into a specific series, since it's a heavier
  /// call than the list endpoints. Cached on disk like [getVodInfo].
  Future<SeriesInfo> getSeriesInfo(
    Account account,
    String seriesId, {
    int maxRetries = _interactiveMaxRetries,
  }) async {
    final cached = await CatalogDatabase.instance.getCachedDetail(
      account.key,
      'series',
      seriesId,
      maxAge: _detailCacheMaxAge,
    );
    if (cached != null) return SeriesInfo.fromJson(cached);

    final url = '${account.apiBaseUrl}&action=get_series_info&series_id=$seriesId';
    final response = await _get(url, maxRetries: maxRetries);

    if (response is! Map<String, dynamic>) {
      throw XtreamApiException('Unexpected series detail response format.',
          kind: XtreamApiErrorKind.badResponse);
    }
    await CatalogDatabase.instance.saveDetail(account.key, 'series', seriesId, response);
    return SeriesInfo.fromJson(response);
  }

  /// Strips Xtream credentials out of an error message before it's shown
  /// anywhere - Dio messages can embed the full request URI, which for
  /// Xtream carries the username and password (as query params on
  /// `player_api.php`, as path segments on a stream URL).
  @visibleForTesting
  static String sanitizeErrorMessage(String message) =>
      redactCredentials(message);

  /// Shared GET + error handling for every call above.
  Future<dynamic> _get(String url, {int maxRetries = _interactiveMaxRetries}) async {
    int attempt = 0;
    while (true) {
      try {
        final response = await _dio.get(url);
        return response.data;
      } on DioException catch (e) {
        final statusCode = e.response?.statusCode;
        // Retry on connection/timeout errors, 503 (Service Unavailable), or
        // 429 (Too Many Requests) - panels commonly throttle the burst of
        // category/stream calls a full catalog sync makes.
        final isRateLimited = statusCode == 429;
        final isRetryable = e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.connectionError ||
            statusCode == 503 ||
            isRateLimited;

        if (isRetryable && attempt < maxRetries) {
          attempt++;
          // Credential-free breadcrumb for the Diagnostics log — status/type
          // only, never the URL (which carries username/password).
          DiagnosticsLog.instance.add(
              'API retry $attempt/$maxRetries (${isRateLimited ? '429' : statusCode?.toString() ?? e.type.name})');
          Duration delay;
          if (isRateLimited) {
            // Honor Retry-After if the server sends one, otherwise back off
            // more aggressively than a plain connection hiccup - 429 means
            // "slow down", not "try again immediately".
            final retryAfter = e.response?.headers.value('retry-after');
            final retryAfterSeconds = int.tryParse(retryAfter ?? '');
            delay = retryAfterSeconds != null
                ? Duration(seconds: retryAfterSeconds)
                : Duration(milliseconds: 1000 * (1 << attempt));
          } else {
            delay = Duration(milliseconds: 200 * (1 << attempt)); // 200, 400, 800ms...
          }
          await Future.delayed(delay);
          continue;
        }

        // Non-retryable or max retries exceeded -> log a breadcrumb (sanitized,
        // no URL) and throw a friendly exception.
        DiagnosticsLog.instance.add(
            'API request failed (${statusCode?.toString() ?? e.type.name})');
        if (e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout) {
          throw XtreamApiException('Connection to server timed out.',
              kind: XtreamApiErrorKind.timeout);
        }
        if (e.type == DioExceptionType.connectionError) {
          throw XtreamApiException(
            'Could not reach server. Check the URL and your connection.',
            kind: XtreamApiErrorKind.unreachable,
          );
        }
        if (isRateLimited) {
          throw XtreamApiException(
            'Server is rate-limiting requests (429). Please try again later.',
            isRateLimited: true,
            kind: XtreamApiErrorKind.rateLimited,
          );
        }
        // For 503 after retries, give a specific message
        if (statusCode == 503) {
          throw XtreamApiException(
            'Server is temporarily unavailable (503). Please try again later.',
            kind: XtreamApiErrorKind.unavailable,
          );
        }
        // A TLS handshake failure arrives as DioExceptionType.unknown, so it
        // would otherwise fall through to the raw text below - which for the
        // common case is "WRONG_VERSION_NUMBER(tls_record.cc:127)", hiding the
        // fact that the fix is one word in the URL.
        switch (classifyTlsFailure(e.error)) {
          case TlsFailure.serverSpeaksPlainHttp:
            throw XtreamApiException(
              'This server does not accept secure connections on that port. '
              'Try http:// instead of https://.',
              kind: XtreamApiErrorKind.httpsNotSupported,
            );
          case TlsFailure.handshakeFailed:
            throw XtreamApiException(
              'Could not establish a secure connection to this server.',
              kind: XtreamApiErrorKind.tlsHandshakeFailed,
            );
          case null:
            break;
        }
        throw XtreamApiException(
          'Request failed: ${sanitizeErrorMessage(e.message ?? e.toString())}',
        );
      }
    }
  }
}