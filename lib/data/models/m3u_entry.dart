/// What a parsed M3U entry represents. M3U is a flat list, so this is inferred
/// (see `M3uParser`): [episode] only when a season+episode number can be read
/// from the title; other on-demand video → [movie]; everything else → [live].
enum M3uEntryKind { live, movie, episode }

/// One `#EXTINF` entry from an M3U/M3U8 playlist: its inferred [kind], display
/// [name], the absolute stream [url], and the optional attributes providers put
/// on the line (`tvg-id` for EPG matching, `tvg-logo`, `group-title`). Episode
/// entries additionally carry the [seriesName]/[seasonNumber]/[episodeNumber]
/// parsed from the title so Phase 2 can reconstruct a series hierarchy.
class M3uEntry {
  final M3uEntryKind kind;
  final String name;
  final String url;

  /// Channel id used to line the entry up with an XMLTV EPG feed (Phase 5).
  final String? tvgId;
  final String? logoUrl;
  final String? groupTitle;

  /// File container extension read from [url] (e.g. `mp4`, `mkv`), for VOD;
  /// null for live or an extension-less URL.
  final String? containerExtension;

  // Episode-only, null otherwise.
  final String? seriesName;
  final int? seasonNumber;
  final int? episodeNumber;

  /// `#EXTVLCOPT` key/values (e.g. `http-user-agent`, `http-referrer`) captured
  /// for later playback-header wiring. Empty when the entry declared none.
  final Map<String, String> vlcOpts;

  const M3uEntry({
    required this.kind,
    required this.name,
    required this.url,
    this.tvgId,
    this.logoUrl,
    this.groupTitle,
    this.containerExtension,
    this.seriesName,
    this.seasonNumber,
    this.episodeNumber,
    this.vlcOpts = const {},
  });
}

/// A parsed M3U playlist: its entries plus the EPG feed URL declared in the
/// `#EXTM3U` header (`url-tvg`/`x-tvg-url`), if any.
class M3uPlaylist {
  final List<M3uEntry> entries;
  final String? epgUrl;

  const M3uPlaylist({required this.entries, this.epgUrl});

  bool get isEmpty => entries.isEmpty;
}
