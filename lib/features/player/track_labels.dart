import 'package:media_kit/media_kit.dart';

/// Human-readable label for a video track (a quality/variant) in the picker.
/// Prefers the resolution (e.g. "720p"), then any bitrate, then the track's
/// title/language, falling back to "Video `<id>`".
String videoTrackLabel(VideoTrack track) {
  final height = track.h;
  final parts = <String>[];
  if (height != null && height > 0) {
    parts.add('${height}p');
  } else {
    final title = track.title?.trim();
    final lang = track.language?.trim();
    if (title != null && title.isNotEmpty) {
      parts.add(title);
    } else if (lang != null && lang.isNotEmpty) {
      parts.add(lang);
    }
  }
  final bitrate = track.bitrate;
  if (bitrate != null && bitrate > 0) parts.add('${(bitrate / 1000000).toStringAsFixed(1)} Mbps');
  return parts.isEmpty ? 'Video ${track.id}' : parts.join(' · ');
}

/// Human-readable label for an audio track in the picker menu.
String audioTrackLabel(AudioTrack track) => _label(
      track.id,
      track.title,
      track.language,
      fallback: 'Audio',
    );

/// Human-readable label for a subtitle track. The special "no" track (which
/// disables subtitles) reads as "Off".
String subtitleTrackLabel(SubtitleTrack track) => _label(
      track.id,
      track.title,
      track.language,
      noLabel: 'Off',
      fallback: 'Subtitle',
    );

/// media_kit tracks carry an id plus optional title/language. Prefer the
/// title, append the language if it adds information, and fall back to
/// "`<kind> <id>`" when the stream labels a track with nothing useful.
String _label(
  String id,
  String? title,
  String? language, {
  String autoLabel = 'Auto',
  String noLabel = 'None',
  String fallback = 'Track',
}) {
  if (id == 'auto') return autoLabel;
  if (id == 'no') return noLabel;

  final cleanTitle = title?.trim();
  final cleanLang = language?.trim();
  final parts = <String>[];
  if (cleanTitle != null && cleanTitle.isNotEmpty) parts.add(cleanTitle);
  if (cleanLang != null &&
      cleanLang.isNotEmpty &&
      cleanLang.toLowerCase() != cleanTitle?.toLowerCase()) {
    parts.add(cleanLang);
  }
  return parts.isEmpty ? '$fallback $id' : parts.join(' · ');
}
