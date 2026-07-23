import 'package:xml/xml.dart';

/// One `<programme>` from an XMLTV EPG feed, normalized to UTC. [channelId]
/// matches an M3U channel's `tvg-id`.
class XmltvProgramme {
  final String channelId;
  final DateTime start;
  final DateTime stop;
  final String title;
  final String description;

  const XmltvProgramme({
    required this.channelId,
    required this.start,
    required this.stop,
    required this.title,
    required this.description,
  });
}

/// Parses an XMLTV document into a flat list of [XmltvProgramme]s — pure, so
/// it's unit-testable without the network or a DB.
///
/// Uses a DOM parse for clarity; for the desktop-first target the transient
/// memory of a large guide is acceptable, and a malformed document yields an
/// empty list rather than throwing. (A streaming parse is a possible future
/// optimization for very large feeds.)
class XmltvParser {
  static List<XmltvProgramme> parse(String xml) {
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(xml);
    } catch (_) {
      return const [];
    }

    final programmes = <XmltvProgramme>[];
    for (final node in doc.findAllElements('programme')) {
      final channelId = node.getAttribute('channel')?.trim() ?? '';
      final start = parseDate(node.getAttribute('start') ?? '');
      final stop = parseDate(node.getAttribute('stop') ?? '');
      if (channelId.isEmpty || start == null || stop == null) continue;
      programmes.add(XmltvProgramme(
        channelId: channelId,
        start: start,
        stop: stop,
        title: _firstText(node, 'title'),
        description: _firstText(node, 'desc'),
      ));
    }
    return programmes;
  }

  /// First non-empty child element [name]'s text (XMLTV repeats these per
  /// language), trimmed; empty string when absent.
  static String _firstText(XmlElement programme, String name) {
    for (final e in programme.findElements(name)) {
      final text = e.innerText.trim();
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  /// Parses an XMLTV timestamp (`YYYYMMDDHHMMSS` optionally followed by a
  /// `+HHMM`/`-HHMM` offset) to UTC, or null if it doesn't match. A missing
  /// offset is treated as already-UTC.
  static DateTime? parseDate(String raw) {
    final s = raw.trim();
    final m =
        RegExp(r'^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})').firstMatch(s);
    if (m == null) return null;
    final base = DateTime.utc(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
      int.parse(m.group(4)!),
      int.parse(m.group(5)!),
      int.parse(m.group(6)!),
    );
    final off = RegExp(r'([+-])(\d{2})(\d{2})\s*$').firstMatch(s);
    if (off == null) return base;
    final sign = off.group(1) == '-' ? -1 : 1;
    final offset = Duration(
      hours: sign * int.parse(off.group(2)!),
      minutes: sign * int.parse(off.group(3)!),
    );
    // A local time of `base` at `offset` is `base - offset` in UTC.
    return base.subtract(offset);
  }
}
