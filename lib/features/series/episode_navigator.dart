import '../../data/models/series_info.dart';

/// A position within a series, as list indices rather than season/episode
/// numbers.
///
/// Indices, deliberately: panels number seasons and episodes however they
/// like - gaps, repeats, a season 0 for specials, episode numbering that
/// restarts mid-season. Arithmetic on those numbers invents episodes that do
/// not exist. The seasons list is already sorted and is the only ordering
/// that is real, so "next" means the next thing in it.
class EpisodeCursor {
  final int seasonIndex;
  final int episodeIndex;

  const EpisodeCursor(this.seasonIndex, this.episodeIndex);

  @override
  bool operator ==(Object other) =>
      other is EpisodeCursor &&
      other.seasonIndex == seasonIndex &&
      other.episodeIndex == episodeIndex;

  @override
  int get hashCode => Object.hash(seasonIndex, episodeIndex);

  @override
  String toString() => 'EpisodeCursor(s$seasonIndex, e$episodeIndex)';
}

/// Moves through a series' episodes, in order, across season boundaries.
///
/// Two different notions of "next" live here on purpose:
///
///   - [nextInSeason] stops at a season finale. Autoplay uses it, so a
///     finished season lets you go rather than pulling you into the next one.
///   - [next] carries on into the following season. The on-screen Next button
///     uses it, because asking for the next episode is a deliberate act.
///
/// Season 0 is treated as an ordinary season, because that is what the panel
/// says it is; specials therefore sit before season 1 in the chain.
class EpisodeNavigator {
  final List<Season> seasons;

  const EpisodeNavigator(this.seasons);

  /// Where [episodeId] sits, or null if this series does not contain it.
  EpisodeCursor? locate(String episodeId) {
    for (var s = 0; s < seasons.length; s++) {
      final episodes = seasons[s].episodes;
      for (var e = 0; e < episodes.length; e++) {
        if (episodes[e].id == episodeId) return EpisodeCursor(s, e);
      }
    }
    return null;
  }

  Episode? episodeAt(EpisodeCursor c) {
    if (c.seasonIndex < 0 || c.seasonIndex >= seasons.length) return null;
    final episodes = seasons[c.seasonIndex].episodes;
    if (c.episodeIndex < 0 || c.episodeIndex >= episodes.length) return null;
    return episodes[c.episodeIndex];
  }

  Season? seasonAt(EpisodeCursor c) =>
      (c.seasonIndex < 0 || c.seasonIndex >= seasons.length)
          ? null
          : seasons[c.seasonIndex];

  /// The next episode in the same season, or null at the season's last one.
  EpisodeCursor? nextInSeason(EpisodeCursor c) {
    final season = seasonAt(c);
    if (season == null) return null;
    final at = c.episodeIndex + 1;
    return at < season.episodes.length ? EpisodeCursor(c.seasonIndex, at) : null;
  }

  /// The next episode anywhere in the series, crossing into later seasons.
  /// Null only at the very last episode of the last season.
  EpisodeCursor? next(EpisodeCursor c) {
    final within = nextInSeason(c);
    if (within != null) return within;
    // Skip seasons the panel listed but left empty, rather than reporting
    // "no next episode" because of a hole in the middle of the series.
    for (var s = c.seasonIndex + 1; s < seasons.length; s++) {
      if (seasons[s].episodes.isNotEmpty) return EpisodeCursor(s, 0);
    }
    return null;
  }

  /// The previous episode anywhere in the series, crossing into earlier
  /// seasons - landing on the *last* episode of the previous one, since that
  /// is what precedes this in viewing order. Null at the series' first
  /// episode.
  EpisodeCursor? previous(EpisodeCursor c) {
    if (c.episodeIndex > 0) {
      return EpisodeCursor(c.seasonIndex, c.episodeIndex - 1);
    }
    for (var s = c.seasonIndex - 1; s >= 0; s--) {
      final episodes = seasons[s].episodes;
      if (episodes.isNotEmpty) return EpisodeCursor(s, episodes.length - 1);
    }
    return null;
  }

  bool hasNext(EpisodeCursor c) => next(c) != null;
  bool hasPrevious(EpisodeCursor c) => previous(c) != null;

  /// Whether finishing [c] should roll straight into another episode.
  /// Season-bounded by design - see the class doc.
  bool shouldAutoplayAfter(EpisodeCursor c) => nextInSeason(c) != null;
}
