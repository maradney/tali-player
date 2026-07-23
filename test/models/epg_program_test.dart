import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/models/epg_program.dart';

void main() {
  group('EpgProgram.fromJson', () {
    test('base64-decodes title and description', () {
      final json = {
        'title': base64.encode(utf8.encode('Morning News')),
        'description': base64.encode(utf8.encode('Headlines & weather')),
        'start_timestamp': '1700000000',
        'stop_timestamp': '1700003600',
      };
      final p = EpgProgram.fromJson(json);
      expect(p.title, 'Morning News');
      expect(p.description, 'Headlines & weather');
    });

    test('falls back to the raw string when a value is not valid base64', () {
      final p = EpgProgram.fromJson({
        'title': 'plain text!!',
        'description': '',
        'start_timestamp': '0',
        'stop_timestamp': '0',
      });
      expect(p.title, 'plain text!!');
      expect(p.description, '');
    });

    test('parses unix-second timestamps into DateTime', () {
      final p = EpgProgram.fromJson({
        'title': '',
        'description': '',
        'start_timestamp': '1700000000',
        'stop_timestamp': '1700003600',
      });
      expect(p.start.millisecondsSinceEpoch, 1700000000 * 1000);
      expect(p.end.millisecondsSinceEpoch, 1700003600 * 1000);
    });

    test('invalid timestamps default to epoch 0', () {
      final p = EpgProgram.fromJson({
        'title': '',
        'description': '',
        'start_timestamp': 'nope',
      });
      expect(p.start.millisecondsSinceEpoch, 0);
      expect(p.end.millisecondsSinceEpoch, 0);
    });
  });

  group('EpgProgram.progress', () {
    test('is 1.0 for a program already over', () {
      final now = DateTime.now();
      final p = EpgProgram(
        title: '',
        description: '',
        start: now.subtract(const Duration(hours: 2)),
        end: now.subtract(const Duration(hours: 1)),
      );
      expect(p.progress, 1.0);
    });

    test('is 0.0 for a program yet to start', () {
      final now = DateTime.now();
      final p = EpgProgram(
        title: '',
        description: '',
        start: now.add(const Duration(hours: 1)),
        end: now.add(const Duration(hours: 2)),
      );
      expect(p.progress, 0.0);
    });

    test('is ~0.5 halfway through', () {
      final now = DateTime.now();
      final p = EpgProgram(
        title: '',
        description: '',
        start: now.subtract(const Duration(minutes: 30)),
        end: now.add(const Duration(minutes: 30)),
      );
      expect(p.progress, closeTo(0.5, 0.05));
    });

    test('is 0.0 when start and end coincide (zero duration)', () {
      final now = DateTime.now();
      final p = EpgProgram(title: '', description: '', start: now, end: now);
      expect(p.progress, 0.0);
    });
  });
}
