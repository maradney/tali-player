/// A log entry recording that something was opened and watched, distinct
/// from [PlaybackProgress] - history is append-only and keeps entries even
/// after a resume position is cleared (finished or manually removed), so
/// it answers "what did I watch" rather than "what can I resume".
class WatchHistoryEntry {
  final String type; // 'live' | 'movie' | 'episode'
  final String id;
  final String name;
  final String? imageUrl;
  final String? seriesId; // episodes only
  final int? seasonNumber; // episodes only
  final int? episodeNum; // episodes only
  // Nullable for backward compatibility with entries logged before this
  // field existed - lets category-level PIN locks be checked from this
  // screen, which only holds a denormalized snapshot.
  final String? categoryId;
  final Map<String, dynamic> extra; // e.g. movie needs containerExtension
  final DateTime watchedAt;

  const WatchHistoryEntry({
    required this.type,
    required this.id,
    required this.name,
    required this.watchedAt,
    this.imageUrl,
    this.seriesId,
    this.seasonNumber,
    this.episodeNum,
    this.categoryId,
    this.extra = const {},
  });

  /// Unique key across all history entry types, e.g. "movie:1234". Used to
  /// dedupe re-watches rather than piling up repeat rows.
  String get key => '$type:$id';

  /// This entry with its poster filled in — used by the history poster
  /// backfill; everything else is immutable by design.
  WatchHistoryEntry withImageUrl(String url) => WatchHistoryEntry(
        type: type,
        id: id,
        name: name,
        imageUrl: url,
        seriesId: seriesId,
        seasonNumber: seasonNumber,
        episodeNum: episodeNum,
        categoryId: categoryId,
        extra: extra,
        watchedAt: watchedAt,
      );

  Map<String, dynamic> toJson() => {
        'type': type,
        'id': id,
        'name': name,
        'imageUrl': imageUrl,
        'seriesId': seriesId,
        'seasonNumber': seasonNumber,
        'episodeNum': episodeNum,
        'categoryId': categoryId,
        'extra': extra,
        'watchedAt': watchedAt.millisecondsSinceEpoch,
      };

  factory WatchHistoryEntry.fromJson(Map<String, dynamic> json) {
    return WatchHistoryEntry(
      type: json['type'] as String,
      id: json['id'] as String,
      name: json['name'] as String,
      imageUrl: json['imageUrl'] as String?,
      seriesId: json['seriesId'] as String?,
      seasonNumber: json['seasonNumber'] as int?,
      episodeNum: json['episodeNum'] as int?,
      categoryId: json['categoryId'] as String?,
      extra: (json['extra'] as Map?)?.cast<String, dynamic>() ?? {},
      watchedAt: DateTime.fromMillisecondsSinceEpoch(json['watchedAt'] as int),
    );
  }
}
