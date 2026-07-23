/// Identifies what's being played, for progress tracking. Live channels
/// don't get one - "resume" only makes sense for on-demand content.
class PlaybackRef {
  final String type; // 'movie' | 'episode'
  final String id; // movie streamId or episode id
  final String? seriesId; // episodes only - which series this belongs to
  final int? seasonNumber; // episodes only
  final int? episodeNum; // episodes only
  // The movie's or series' category - carried through so watch history can
  // record it for category-level PIN lock checks.
  final String? categoryId;

  const PlaybackRef({
    required this.type,
    required this.id,
    this.seriesId,
    this.seasonNumber,
    this.episodeNum,
    this.categoryId,
  });
}

/// A saved playback position for one movie or episode, persisted so the
/// player can offer to resume where the user left off, and so a series'
/// detail screen can jump straight to the season/episode last watched.
class PlaybackProgress {
  final String type;
  final String id;
  final Duration position;
  final Duration total;
  final String? seriesId;
  final int? seasonNumber;
  final int? episodeNum;
  final DateTime updatedAt;

  const PlaybackProgress({
    required this.type,
    required this.id,
    required this.position,
    required this.total,
    required this.updatedAt,
    this.seriesId,
    this.seasonNumber,
    this.episodeNum,
  });

  String get key => '$type:$id';

  Map<String, dynamic> toJson() => {
        'type': type,
        'id': id,
        'positionMs': position.inMilliseconds,
        'totalMs': total.inMilliseconds,
        'seriesId': seriesId,
        'seasonNumber': seasonNumber,
        'episodeNum': episodeNum,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
      };

  factory PlaybackProgress.fromJson(Map<String, dynamic> json) => PlaybackProgress(
        type: json['type'] as String,
        id: json['id'] as String,
        position: Duration(milliseconds: json['positionMs'] as int),
        total: Duration(milliseconds: json['totalMs'] as int),
        seriesId: json['seriesId'] as String?,
        seasonNumber: json['seasonNumber'] as int?,
        episodeNum: json['episodeNum'] as int?,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(json['updatedAt'] as int),
      );
}
