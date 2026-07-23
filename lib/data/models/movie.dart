class Movie {
  final String streamId;
  final String name;
  final String? posterUrl; // "stream_icon" in the API
  final String categoryId;
  final String containerExtension; // e.g. "mp4", "mkv" - needed for the URL

  /// IMDb-style numeric score (e.g. "7.4") - some panels include this
  /// directly in the list response, opportunistic like everywhere else.
  final String? rating;

  /// When the provider added this to their panel, as a unix epoch in
  /// SECONDS (the "added" field in get_vod_streams), or null if the panel
  /// doesn't report it. Drives the Recently Added view; not every panel
  /// populates it.
  final int? addedAt;

  /// Absolute stream URL, set only for M3U playlists. Null for Xtream, whose
  /// URL is built from the account — see [streamUrl].
  final String? url;

  const Movie({
    required this.streamId,
    required this.name,
    required this.categoryId,
    required this.containerExtension,
    this.posterUrl,
    this.rating,
    this.addedAt,
    this.url,
  });

  static String? _parseRating(dynamic value) {
    final n = double.tryParse(value?.toString().trim() ?? '');
    return n != null && n > 0 ? n.toString() : null;
  }

  factory Movie.fromJson(Map<String, dynamic> json) {
    return Movie(
      streamId: json['stream_id'].toString(),
      name: json['name']?.toString() ?? 'Unnamed movie',
      categoryId: json['category_id']?.toString() ?? '',
      // Not every panel includes this - default to mp4 as the most common.
      containerExtension:
          (json['container_extension'] as String?)?.isNotEmpty == true
              ? json['container_extension']
              : 'mp4',
      posterUrl: (json['stream_icon'] as String?)?.isNotEmpty == true
          ? json['stream_icon']
          : null,
      rating: _parseRating(json['rating']),
      addedAt: int.tryParse(json['added']?.toString() ?? ''),
    );
  }

  /// Format: {server}/movie/{username}/{password}/{stream_id}.{ext}
  String streamUrl({
    required String serverUrl,
    required String username,
    required String password,
  }) {
    return '$serverUrl/movie/$username/$password/$streamId.$containerExtension';
  }
}