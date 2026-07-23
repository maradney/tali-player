class Episode {
  final String id; // used as the stream id in the playback URL
  final String title;
  final int episodeNum;
  final String containerExtension;

  /// Absolute stream URL, set only for M3U playlists. Null for Xtream, whose
  /// URL is built from the account — see [streamUrl].
  final String? url;

  const Episode({
    required this.id,
    required this.title,
    required this.episodeNum,
    required this.containerExtension,
    this.url,
  });

  factory Episode.fromJson(Map<String, dynamic> json) {
    return Episode(
      id: json['id'].toString(),
      title: json['title']?.toString() ?? 'Episode',
      episodeNum: int.tryParse(json['episode_num']?.toString() ?? '') ?? 0,
      containerExtension:
          (json['container_extension'] as String?)?.isNotEmpty == true
              ? json['container_extension']
              : 'mp4',
    );
  }

  /// Format: {server}/series/{username}/{password}/{episode_id}.{ext}
  String streamUrl({
    required String serverUrl,
    required String username,
    required String password,
  }) {
    return '$serverUrl/series/$username/$password/$id.$containerExtension';
  }
}

class Season {
  final int seasonNumber;
  final String name;
  final List<Episode> episodes;

  const Season({
    required this.seasonNumber,
    required this.name,
    required this.episodes,
  });
}

/// Full detail for one series - the result of get_series_info.
/// Xtream's response shape is a bit awkward: season metadata and the
/// episode list are two separate top-level keys that we join here so
/// the UI just gets a clean `List<Season>`, each with its episodes attached.
/// The "info" key holds overview fields (plot/cast/director/genre) shown
/// on the series detail screen above the season/episode picker.
class SeriesInfo {
  final List<Season> seasons;
  final String? plot;
  final String? cast;
  final String? director;
  final String? genre;
  final String? coverUrl;

  /// IMDb-style numeric score (e.g. "7.4"), not a content/age rating -
  /// only present when the provider's panel scrapes TMDB.
  final String? rating;

  /// Content/age rating (e.g. "PG-13", "TV-MA") - opportunistic, most
  /// panels don't populate this at all.
  final String? ageRating;

  /// Four-digit release year, when the panel reports one (from "year" or a
  /// "releaseDate"). Captured for the enhanced-search catalog (year faceting).
  final int? year;

  const SeriesInfo({
    required this.seasons,
    this.plot,
    this.cast,
    this.director,
    this.genre,
    this.coverUrl,
    this.rating,
    this.ageRating,
    this.year,
  });

  static String? _nonEmpty(dynamic value) {
    final s = value?.toString().trim();
    return s?.isNotEmpty == true ? s : null;
  }

  /// Pulls a plausible 4-digit year from the panel's "year"/"releaseDate"
  /// fields (names vary), rejecting nonsense outside a sane range.
  static int? parseYear(Map<String, dynamic> info) {
    final raw = (info['year'] ??
            info['releaseDate'] ??
            info['releasedate'] ??
            info['release_date'])
        ?.toString();
    final match = RegExp(r'(\d{4})').firstMatch(raw ?? '');
    final year = match == null ? null : int.tryParse(match.group(1)!);
    return (year != null && year >= 1870 && year <= 2100) ? year : null;
  }

  factory SeriesInfo.fromJson(Map<String, dynamic> json) {
    final seasonsMeta = (json['seasons'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    final episodesByseason =
        (json['episodes'] as Map<String, dynamic>? ?? {});
    final info = json['info'] as Map<String, dynamic>? ?? {};

    final seasons = <Season>[];

    // Prefer the season list from "seasons" for names/ordering, but fall
    // back to whatever keys exist in "episodes" if "seasons" is missing -
    // some panels only populate one of the two.
    final seasonNumbers = seasonsMeta.isNotEmpty
        ? seasonsMeta
            .map((s) => int.tryParse(s['season_number']?.toString() ?? '') ?? 0)
            .toList()
        : episodesByseason.keys.map((k) => int.tryParse(k) ?? 0).toList();

    for (final seasonNumber in seasonNumbers) {
      final meta = seasonsMeta.firstWhere(
        (s) => (int.tryParse(s['season_number']?.toString() ?? '') ?? 0) ==
            seasonNumber,
        orElse: () => {},
      );
      final episodesJson =
          (episodesByseason[seasonNumber.toString()] as List? ?? [])
              .cast<Map<String, dynamic>>();

      final episodes = <Episode>[];
      for (final e in episodesJson) {
        try {
          episodes.add(Episode.fromJson(e));
        } catch (_) {
          continue; // skip malformed entries rather than failing the season
        }
      }
      episodes.sort((a, b) => a.episodeNum.compareTo(b.episodeNum));

      seasons.add(Season(
        seasonNumber: seasonNumber,
        name: meta['name']?.toString() ?? 'Season $seasonNumber',
        episodes: episodes,
      ));
    }

    seasons.sort((a, b) => a.seasonNumber.compareTo(b.seasonNumber));
    return SeriesInfo(
      seasons: seasons,
      plot: _nonEmpty(info['plot']),
      cast: _nonEmpty(info['cast']),
      director: _nonEmpty(info['director']),
      genre: _nonEmpty(info['genre']),
      coverUrl: _nonEmpty(info['cover']),
      rating: _nonEmpty(info['rating']),
      // Field name varies by panel - check the common variants in order.
      ageRating: _nonEmpty(info['mpaa_rating']) ??
          _nonEmpty(info['age']) ??
          _nonEmpty(info['rating_mpaa']),
      year: parseYear(info),
    );
  }
}