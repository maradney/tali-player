import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/models/account.dart';
import 'package:iptv_player/data/models/channel.dart';
import 'package:iptv_player/data/models/epg_program.dart';
import 'package:iptv_player/data/sources/m3u_media_source.dart';
import 'package:iptv_player/data/sources/xtream_media_source.dart';
import 'package:iptv_player/features/live_tv/catchup.dart';

import '../support/test_support.dart';

Channel _channel({bool archive = true, int days = 2}) => Channel(
      streamId: '55',
      name: 'One',
      categoryId: '1',
      tvArchive: archive,
      tvArchiveDays: days,
    );

EpgProgram _programme(DateTime start, {Duration length = const Duration(hours: 1)}) =>
    EpgProgram(title: 'Show', description: '', start: start, end: start.add(length));

void main() {
  final now = DateTime(2026, 7, 23, 20, 0);

  group('Channel.fromJson archive fields', () {
    test('parses int and string forms of tv_archive/duration', () {
      final a = Channel.fromJson(
          {'stream_id': 1, 'name': 'A', 'tv_archive': 1, 'tv_archive_duration': 7});
      expect(a.tvArchive, isTrue);
      expect(a.tvArchiveDays, 7);

      final b = Channel.fromJson({
        'stream_id': 2,
        'name': 'B',
        'tv_archive': '1',
        'tv_archive_duration': '3'
      });
      expect(b.tvArchive, isTrue);
      expect(b.tvArchiveDays, 3);
    });

    test('defaults to no archive when absent or 0', () {
      final c = Channel.fromJson({'stream_id': 3, 'name': 'C'});
      expect(c.tvArchive, isFalse);
      final d = Channel.fromJson(
          {'stream_id': 4, 'name': 'D', 'tv_archive': 0});
      expect(d.tvArchive, isFalse);
    });

    test('a truthy archive with missing duration falls back to 1 day', () {
      final e = Channel.fromJson({'stream_id': 5, 'name': 'E', 'tv_archive': 1});
      expect(e.tvArchiveDays, 1);
    });
  });

  group('catchupAvailable', () {
    test('true for a programme that already ended inside the window', () {
      final p = _programme(now.subtract(const Duration(hours: 3)));
      expect(catchupAvailable(_channel(), p, now: now), isTrue);
    });

    test('true for a currently-airing programme (restart from beginning)', () {
      final p = _programme(now.subtract(const Duration(minutes: 20)));
      expect(catchupAvailable(_channel(), p, now: now), isTrue);
    });

    test('false for a future programme', () {
      final p = _programme(now.add(const Duration(hours: 1)));
      expect(catchupAvailable(_channel(), p, now: now), isFalse);
    });

    test('false when the start has aged out of the archive window', () {
      final p = _programme(now.subtract(const Duration(days: 3)));
      expect(catchupAvailable(_channel(days: 2), p, now: now), isFalse);
    });

    test('false when the channel has no archive at all', () {
      final p = _programme(now.subtract(const Duration(hours: 1)));
      expect(catchupAvailable(_channel(archive: false), p, now: now), isFalse);
    });
  });

  group('timeshift URL', () {
    test('Xtream builds the /timeshift/ path with a zero-padded stamp', () {
      final source = XtreamMediaSource(accountNamed('ts'));
      final url = source.timeshiftUrl(
        _channel(),
        DateTime(2026, 7, 5, 9, 5),
        const Duration(minutes: 60),
      );
      expect(
        url,
        'http://host:8080/timeshift/ts/pw-ts/60/2026-07-05:09-05/55.ts',
      );
      expect(source.supportsCatchup(_channel()), isTrue);
      expect(source.supportsCatchup(_channel(archive: false)), isFalse);
    });

    test('duration is clamped to at least one minute', () {
      final source = XtreamMediaSource(accountNamed('ts'));
      final url = source.timeshiftUrl(
          _channel(), DateTime(2026, 7, 5, 9, 5), Duration.zero);
      expect(url, contains('/1/2026-07-05:09-05/'));
    });

    test('M3U has no timeshift support', () {
      const m3u = Account.m3u(name: 'M', url: 'http://host/list.m3u8');
      final source = M3uMediaSource(m3u, fetch: (_) async => '');
      expect(source.supportsCatchup(_channel()), isFalse);
      expect(
          source.timeshiftUrl(
              _channel(), DateTime(2026, 7, 5), const Duration(minutes: 30)),
          isNull);
    });
  });
}
