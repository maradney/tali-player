import 'channel.dart' show castHeaders;
import 'favorite_item.dart';
import 'playback_progress.dart';

/// Where an offline download currently sits. Live progress (bytes) is tracked
/// separately in DownloadService, not persisted here.
enum DownloadStatus { queued, downloading, completed, failed }

/// A movie or series episode saved (or being saved) to disk for offline
/// playback. Carries enough to render a tile, rebuild a [PlaybackRef] so
/// offline resume works, and derive the on-disk filename. Live channels are
/// never downloaded (a continuous stream has no "download").
class DownloadItem {
  final String type; // 'movie' | 'episode'
  final String id; // movie streamId or episode id
  final String name; // display title (episode title for episodes)
  final String? seriesName; // episodes only — for a nicer tile/history label
  final String? seriesId; // episodes only
  final int? seasonNumber; // episodes only
  final int? episodeNum; // episodes only
  final String categoryId;
  final String? posterUrl;
  final String containerExtension; // e.g. 'mp4', 'mkv' — also the file's ext

  /// The remote stream URL, persisted so a failed download can be retried
  /// without the caller having to rebuild it. It carries the account's
  /// credentials as query-less path segments; the whole record is per-account
  /// and wiped when the playlist/profile is deleted, same as favorites.
  final String remoteUrl;

  /// HTTP headers the transfer must send (M3U's default browser User-Agent —
  /// a UA-picky server that streams fine would otherwise 403 the download).
  /// Persisted alongside [remoteUrl] so retries after a restart keep them.
  /// Null for Xtream, whose panels expect plain requests.
  final Map<String, String>? headers;

  final DownloadStatus status;

  /// When the user queued this, unix epoch millis — newest-first ordering.
  final int addedAt;

  const DownloadItem({
    required this.type,
    required this.id,
    required this.name,
    required this.categoryId,
    required this.containerExtension,
    required this.remoteUrl,
    required this.status,
    required this.addedAt,
    this.headers,
    this.seriesName,
    this.seriesId,
    this.seasonNumber,
    this.episodeNum,
    this.posterUrl,
  });

  /// Stable identity within one account's list (mirrors the 'type:id'
  /// convention used by favorites/watch-history/PIN locks).
  String get key => '$type:$id';

  /// The on-disk filename — flat and collision-free per account since ids are
  /// unique per type. Pure (no I/O) so it's easy to unit-test.
  String get fileName => '${type}_$id.$containerExtension';

  /// The favorite/watch-history snapshot for playing this download: episodes
  /// map to their parent series (matching how favorites and history label
  /// them), movies to themselves. Handing this to the player gives offline
  /// playback the same star toggle and — crucially — puts the poster on the
  /// watch-history entry it records.
  FavoriteItem toFavoriteItem() => FavoriteItem(
        type: type == 'episode' ? 'series' : 'movie',
        id: type == 'episode' ? (seriesId ?? id) : id,
        name: seriesName ?? name,
        imageUrl: posterUrl,
        categoryId: categoryId,
        extra: {
          if (type == 'movie') 'containerExtension': containerExtension,
        },
      );

  /// Rebuilds the resume reference so a downloaded item still remembers its
  /// position when played offline.
  PlaybackRef get playbackRef => PlaybackRef(
        type: type,
        id: id,
        seriesId: seriesId,
        seasonNumber: seasonNumber,
        episodeNum: episodeNum,
        categoryId: categoryId,
      );

  DownloadItem copyWith({DownloadStatus? status}) => DownloadItem(
        type: type,
        id: id,
        name: name,
        categoryId: categoryId,
        containerExtension: containerExtension,
        remoteUrl: remoteUrl,
        status: status ?? this.status,
        addedAt: addedAt,
        headers: headers,
        seriesName: seriesName,
        seriesId: seriesId,
        seasonNumber: seasonNumber,
        episodeNum: episodeNum,
        posterUrl: posterUrl,
      );

  Map<String, dynamic> toJson() => {
        'type': type,
        'id': id,
        'name': name,
        'seriesName': seriesName,
        'seriesId': seriesId,
        'seasonNumber': seasonNumber,
        'episodeNum': episodeNum,
        'categoryId': categoryId,
        'posterUrl': posterUrl,
        'containerExtension': containerExtension,
        'remoteUrl': remoteUrl,
        'headers': headers,
        'status': status.name,
        'addedAt': addedAt,
      };

  factory DownloadItem.fromJson(Map<String, dynamic> json) => DownloadItem(
        type: json['type'] as String,
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        seriesName: json['seriesName'] as String?,
        seriesId: json['seriesId'] as String?,
        seasonNumber: json['seasonNumber'] as int?,
        episodeNum: json['episodeNum'] as int?,
        categoryId: json['categoryId'] as String? ?? '',
        posterUrl: json['posterUrl'] as String?,
        containerExtension: json['containerExtension'] as String? ?? 'mp4',
        remoteUrl: json['remoteUrl'] as String? ?? '',
        headers: castHeaders(json['headers']),
        status: DownloadStatus.values.firstWhere(
          (s) => s.name == json['status'],
          orElse: () => DownloadStatus.failed,
        ),
        addedAt: json['addedAt'] as int? ?? 0,
      );
}
