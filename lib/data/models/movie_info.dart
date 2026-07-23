/// Overview detail for one movie - the result of get_vod_info. Only the
/// "info" block is needed here (plot/cast/director/genre); playback still
/// uses the Movie object already loaded from the category list.
class MovieInfo {
  final String? plot;
  final String? cast;
  final String? director;
  final String? genre;

  /// IMDb-style numeric score (e.g. "7.4"), not a content/age rating -
  /// only present when the provider's panel scrapes TMDB.
  final String? rating;

  /// Content/age rating (e.g. "PG-13", "TV-MA") - opportunistic, most
  /// panels don't populate this at all.
  final String? ageRating;

  /// Four-digit release year, when the panel reports one (from "year" or a
  /// "releasedate"). The category list doesn't carry this, so it's captured
  /// here for the enhanced-search catalog (year faceting).
  final int? year;

  const MovieInfo({
    this.plot,
    this.cast,
    this.director,
    this.genre,
    this.rating,
    this.ageRating,
    this.year,
  });

  static String? _nonEmpty(dynamic value) {
    final s = value?.toString().trim();
    return s?.isNotEmpty == true ? s : null;
  }

  /// Pulls a plausible 4-digit year from the panel's "year"/"releasedate"
  /// fields (names vary), rejecting nonsense outside a sane range.
  static int? parseYear(Map<String, dynamic> info) {
    final raw = (info['year'] ??
            info['releasedate'] ??
            info['release_date'] ??
            info['releaseDate'])
        ?.toString();
    final match = RegExp(r'(\d{4})').firstMatch(raw ?? '');
    final year = match == null ? null : int.tryParse(match.group(1)!);
    return (year != null && year >= 1870 && year <= 2100) ? year : null;
  }

  factory MovieInfo.fromJson(Map<String, dynamic> json) {
    final info = json['info'] as Map<String, dynamic>? ?? {};
    return MovieInfo(
      plot: _nonEmpty(info['plot']),
      cast: _nonEmpty(info['cast']),
      director: _nonEmpty(info['director']),
      genre: _nonEmpty(info['genre']),
      rating: _nonEmpty(info['rating']),
      // Field name varies by panel - check the common variants in order.
      ageRating: _nonEmpty(info['mpaa_rating']) ??
          _nonEmpty(info['age']) ??
          _nonEmpty(info['rating_mpaa']),
      year: parseYear(info),
    );
  }
}
