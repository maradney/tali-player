import '../models/m3u_entry.dart';

/// Parses M3U / M3U8 playlist text into an [M3uPlaylist] — pure (no I/O), so
/// the whole thing is unit-testable. Deliberately lenient: a malformed line is
/// skipped rather than aborting the parse (providers' playlists vary wildly).
///
/// Recognized shape:
/// ```
/// #EXTM3U url-tvg="http://.../epg.xml"
/// #EXTINF:-1 tvg-id="cnn" tvg-logo="http://..." group-title="News",CNN HD
/// #EXTVLCOPT:http-user-agent=Mozilla/5.0
/// http://host/live/user/pass/123.ts
/// ```
class M3uParser {
  /// Video container extensions that mark an entry as on-demand (VOD) rather
  /// than a live stream (which is typically `.ts`/`.m3u8` or extension-less).
  static const _vodExtensions = {
    'mp4', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'm4v', 'mpg', 'mpeg', 'webm',
  };

  static final _attrPattern = RegExp(r'([\w-]+)="([^"]*)"');

  // Season/episode patterns, tried in order. Group 1 = season, group 2 = number.
  static final _episodePatterns = <RegExp>[
    RegExp(r'[Ss](\d{1,2})[\s._-]*[Ee](\d{1,3})'), // S01E02, s1e2, S01.E02
    RegExp(r'[Ss]eason\s*(\d{1,2}).*?[Ee]pisode\s*(\d{1,3})'), // Season 1 Episode 2
    // NxNN (1x02), guarded so a resolution like 1920x1080 doesn't match.
    RegExp(r'(?<!\d)(\d{1,2})[xX](\d{1,3})(?!\d)'),
  ];

  static M3uPlaylist parse(String content) {
    final lines = content.split('\n');
    String? epgUrl;
    final entries = <M3uEntry>[];

    // Attributes accumulate across the #EXTINF (+ any #EXTVLCOPT/#EXTGRP) lines
    // until the URL line closes the entry.
    _PendingEntry? pending;

    for (var raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) continue;

      if (line.startsWith('#EXTM3U')) {
        epgUrl ??= _headerEpgUrl(line);
      } else if (line.startsWith('#EXTINF:')) {
        pending = _parseExtInf(line.substring('#EXTINF:'.length));
      } else if (line.startsWith('#EXTVLCOPT:')) {
        pending?.addVlcOpt(line.substring('#EXTVLCOPT:'.length));
      } else if (line.startsWith('#EXTGRP:')) {
        // Alternate way to declare the group; only used if group-title was absent.
        pending?.groupTitle ??= line.substring('#EXTGRP:'.length).trim();
      } else if (line.startsWith('#')) {
        continue; // some other directive we don't need
      } else if (pending != null) {
        // A non-comment line closes the current entry: it's the stream URL.
        entries.add(pending.build(line));
        pending = null;
      }
    }

    return M3uPlaylist(entries: entries, epgUrl: epgUrl);
  }

  /// Reads `url-tvg` / `x-tvg-url` (or the older `tvg-url`) from the header.
  static String? _headerEpgUrl(String header) {
    for (final m in _attrPattern.allMatches(header)) {
      final key = m.group(1)!.toLowerCase();
      if (key == 'url-tvg' || key == 'x-tvg-url' || key == 'tvg-url') {
        final v = m.group(2)!.trim();
        // Some headers list several comma-separated feeds; take the first.
        final first = v.split(',').first.trim();
        if (first.isNotEmpty) return first;
      }
    }
    return null;
  }

  static _PendingEntry _parseExtInf(String rest) {
    // Split "duration attrs" from "Display Name" at the first UNQUOTED comma —
    // attribute values can themselves contain commas.
    var commaIdx = -1;
    var inQuotes = false;
    for (var i = 0; i < rest.length; i++) {
      final ch = rest[i];
      if (ch == '"') {
        inQuotes = !inQuotes;
      } else if (ch == ',' && !inQuotes) {
        commaIdx = i;
        break;
      }
    }
    final meta = commaIdx >= 0 ? rest.substring(0, commaIdx) : rest;
    final displayName = commaIdx >= 0 ? rest.substring(commaIdx + 1).trim() : '';

    final attrs = <String, String>{};
    for (final m in _attrPattern.allMatches(meta)) {
      attrs[m.group(1)!.toLowerCase()] = m.group(2)!;
    }

    return _PendingEntry(
      name: displayName.isNotEmpty
          ? displayName
          : (attrs['tvg-name']?.trim().isNotEmpty == true
              ? attrs['tvg-name']!.trim()
              : 'Unnamed'),
      tvgId: _nonEmpty(attrs['tvg-id']),
      logoUrl: _nonEmpty(attrs['tvg-logo']),
      groupTitle: _nonEmpty(attrs['group-title']),
    );
  }

  static String? _nonEmpty(String? v) =>
      (v != null && v.trim().isNotEmpty) ? v.trim() : null;

  /// The file container extension of a URL's last path segment, lowercased, or
  /// null when there isn't a plausible one. Strips any query string first.
  static String? extensionOf(String url) {
    var path = url;
    final q = path.indexOf('?');
    if (q >= 0) path = path.substring(0, q);
    final slash = path.lastIndexOf('/');
    final segment = slash >= 0 ? path.substring(slash + 1) : path;
    final dot = segment.lastIndexOf('.');
    if (dot < 0 || dot == segment.length - 1) return null;
    final ext = segment.substring(dot + 1).toLowerCase();
    return RegExp(r'^[a-z0-9]{1,5}$').hasMatch(ext) ? ext : null;
  }

  /// Reads `series / season / episode` from a title, or null when it isn't
  /// episodic. Series name is the text before the marker, trimmed of trailing
  /// separators.
  static ({String series, int season, int number})? parseEpisode(String name) {
    for (final pattern in _episodePatterns) {
      final m = pattern.firstMatch(name);
      if (m == null) continue;
      final season = int.tryParse(m.group(1)!);
      final number = int.tryParse(m.group(2)!);
      if (season == null || number == null) continue;
      var series = name.substring(0, m.start).trim();
      series = series.replaceAll(RegExp(r'[\s._\-]+$'), '').trim();
      return (
        series: series.isEmpty ? name.trim() : series,
        season: season,
        number: number,
      );
    }
    return null;
  }

  /// Classifies an entry from its URL + title. Episodes win when a season+
  /// episode can be read; other on-demand video (an Xtream `/movie/` or
  /// `/series/` path, or a VOD file extension) is a movie; the rest is live.
  static M3uEntryKind classify(String url, String name) {
    if (parseEpisode(name) != null) return M3uEntryKind.episode;
    final lower = url.toLowerCase();
    if (lower.contains('/movie/') || lower.contains('/series/')) {
      return M3uEntryKind.movie;
    }
    final ext = extensionOf(lower);
    if (ext != null && _vodExtensions.contains(ext)) return M3uEntryKind.movie;
    return M3uEntryKind.live;
  }
}

/// Mutable accumulator for the lines that make up one entry until its URL
/// closes it. Kept private — callers only ever see the finished [M3uEntry].
class _PendingEntry {
  final String name;
  final String? tvgId;
  final String? logoUrl;
  String? groupTitle;
  final Map<String, String> vlcOpts = {};

  _PendingEntry({
    required this.name,
    this.tvgId,
    this.logoUrl,
    this.groupTitle,
  });

  void addVlcOpt(String opt) {
    final eq = opt.indexOf('=');
    if (eq <= 0) return;
    vlcOpts[opt.substring(0, eq).trim().toLowerCase()] =
        opt.substring(eq + 1).trim();
  }

  M3uEntry build(String url) {
    final kind = M3uParser.classify(url, name);
    final episode =
        kind == M3uEntryKind.episode ? M3uParser.parseEpisode(name) : null;
    return M3uEntry(
      kind: kind,
      name: name,
      url: url,
      tvgId: tvgId,
      logoUrl: logoUrl,
      groupTitle: groupTitle,
      containerExtension:
          kind == M3uEntryKind.live ? null : M3uParser.extensionOf(url),
      seriesName: episode?.series,
      seasonNumber: episode?.season,
      episodeNumber: episode?.number,
      vlcOpts: Map.unmodifiable(vlcOpts),
    );
  }
}
