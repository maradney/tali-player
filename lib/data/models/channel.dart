/// Coerces a stored/JSON-decoded headers value (a `Map<String, dynamic>`) to a
/// `Map<String, String>`, or null when there's nothing usable.
Map<String, String>? castHeaders(Object? value) {
  if (value is! Map || value.isEmpty) return null;
  return value.map((k, v) => MapEntry(k.toString(), v.toString()));
}

class Channel {
  final String streamId;
  final String name;
  final String? logoUrl; // "stream_icon" in the API
  final String categoryId;

  /// Absolute stream URL, set only for M3U playlists (where each entry carries
  /// its own URL). Null for Xtream, whose URL is built from the account — see
  /// [streamUrl]. The source's `liveUrl` returns this verbatim when present.
  final String? url;

  /// HTTP headers a stream requires (from an M3U entry's `#EXTVLCOPT`, e.g. a
  /// `User-Agent`/`Referer`). Null/empty for Xtream and most channels.
  final Map<String, String>? headers;

  /// Whether the panel advertises catch-up (`tv_archive`) for this channel —
  /// past programmes can be replayed via a timeshift URL.
  final bool tvArchive;

  /// How many days back the archive reaches (`tv_archive_duration`). Only
  /// meaningful when [tvArchive] is true; panels that omit it get 1 day.
  final int tvArchiveDays;

  const Channel({
    required this.streamId,
    required this.name,
    required this.categoryId,
    this.logoUrl,
    this.url,
    this.headers,
    this.tvArchive = false,
    this.tvArchiveDays = 1,
  });

  factory Channel.fromJson(Map<String, dynamic> json) {
    // Panels ship these as int or string ("1", "7") interchangeably.
    final archive = int.tryParse(json['tv_archive']?.toString() ?? '') ?? 0;
    final archiveDays =
        int.tryParse(json['tv_archive_duration']?.toString() ?? '') ?? 0;
    return Channel(
      streamId: json['stream_id'].toString(),
      name: json['name']?.toString() ?? 'Unnamed channel',
      categoryId: json['category_id']?.toString() ?? '',
      logoUrl: (json['stream_icon'] as String?)?.isNotEmpty == true
          ? json['stream_icon']
          : null,
      tvArchive: archive == 1,
      tvArchiveDays: archiveDays > 0 ? archiveDays : 1,
    );
  }

  /// Builds the actual playable stream URL for this channel.
  /// Format: {server}/live/{username}/{password}/{stream_id}.ts
  String streamUrl({
    required String serverUrl,
    required String username,
    required String password,
  }) {
    return '$serverUrl/live/$username/$password/$streamId.ts';
  }
}