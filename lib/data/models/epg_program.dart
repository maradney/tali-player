import 'dart:convert';

class EpgProgram {
  final String title;
  final String description;
  final DateTime start;
  final DateTime end;

  const EpgProgram({
    required this.title,
    required this.description,
    required this.start,
    required this.end,
  });

  /// How far through this program we currently are, 0.0 to 1.0.
  /// Used to drive the little progress bar under "Now:" in the channel list.
  double get progress {
    final total = end.difference(start).inSeconds;
    if (total <= 0) return 0;
    final elapsed = DateTime.now().difference(start).inSeconds;
    return (elapsed / total).clamp(0.0, 1.0);
  }

  factory EpgProgram.fromJson(Map<String, dynamic> json) {
    return EpgProgram(
      title: _decodeBase64(json['title']),
      description: _decodeBase64(json['description']),
      // start_timestamp/stop_timestamp are unix epoch seconds, as strings.
      start: DateTime.fromMillisecondsSinceEpoch(
        (int.tryParse(json['start_timestamp']?.toString() ?? '') ?? 0) * 1000,
      ),
      end: DateTime.fromMillisecondsSinceEpoch(
        (int.tryParse(json['stop_timestamp']?.toString() ?? '') ?? 0) * 1000,
      ),
    );
  }

  /// Xtream panels base64-encode title/description. A few oddball panels
  /// don't - so if decoding fails or produces garbage, fall back to the
  /// raw string rather than crashing the whole EPG fetch.
  static String _decodeBase64(dynamic value) {
    final raw = value?.toString() ?? '';
    if (raw.isEmpty) return '';
    try {
      return utf8.decode(base64.decode(raw));
    } catch (_) {
      return raw;
    }
  }
}