import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/sources/xmltv_parser.dart';

void main() {
  group('XmltvParser.parseDate', () {
    test('parses a timestamp with a +offset to UTC', () {
      // 12:00 at UTC+2 is 10:00 UTC.
      final utc = XmltvParser.parseDate('20260719120000 +0200');
      expect(utc, DateTime.utc(2026, 7, 19, 10, 0, 0));
    });

    test('parses a timestamp with a -offset to UTC', () {
      // 12:00 at UTC-5 is 17:00 UTC.
      final utc = XmltvParser.parseDate('20260719120000 -0500');
      expect(utc, DateTime.utc(2026, 7, 19, 17, 0, 0));
    });

    test('treats a missing offset as UTC', () {
      expect(XmltvParser.parseDate('20260719120000'),
          DateTime.utc(2026, 7, 19, 12, 0, 0));
    });

    test('returns null for a non-timestamp', () {
      expect(XmltvParser.parseDate('nonsense'), isNull);
    });
  });

  group('XmltvParser.parse', () {
    const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<tv>
  <channel id="cnn.us"><display-name>CNN</display-name></channel>
  <programme start="20260719120000 +0000" stop="20260719130000 +0000" channel="cnn.us">
    <title lang="en">World News</title>
    <desc lang="en">Headlines.</desc>
  </programme>
  <programme start="20260719130000 +0000" stop="20260719140000 +0000" channel="cnn.us">
    <title>Weather</title>
  </programme>
  <programme start="20260719120000 +0000" stop="20260719130000 +0000" channel="bbc.uk">
    <title>Breakfast</title>
  </programme>
</tv>''';

    test('reads programmes with channel, times, title and description', () {
      final programmes = XmltvParser.parse(xml);
      expect(programmes, hasLength(3));
      final first = programmes.first;
      expect(first.channelId, 'cnn.us');
      expect(first.title, 'World News');
      expect(first.description, 'Headlines.');
      expect(first.start, DateTime.utc(2026, 7, 19, 12));
      expect(first.stop, DateTime.utc(2026, 7, 19, 13));
    });

    test('tolerates a programme with no description', () {
      final weather = XmltvParser.parse(xml).firstWhere((p) => p.title == 'Weather');
      expect(weather.description, isEmpty);
    });

    test('skips programmes missing a channel or times', () {
      const bad = '<tv><programme start="20260719120000" stop="20260719130000">'
          '<title>No channel</title></programme></tv>';
      expect(XmltvParser.parse(bad), isEmpty);
    });

    test('returns empty for malformed xml rather than throwing', () {
      expect(XmltvParser.parse('<tv><programme'), isEmpty);
    });
  });
}
