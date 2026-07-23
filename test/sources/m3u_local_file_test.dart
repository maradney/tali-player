import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/models/account.dart';
import 'package:iptv_player/data/sources/m3u_media_source.dart';

const _playlist = '''
#EXTM3U
#EXTINF:-1 tvg-id="one" group-title="News",Channel One
http://host/live/1.ts
''';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('m3u_local');
  });

  tearDown(() async {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  test('the default fetcher reads a bare local file path', () async {
    final file = File('${dir.path}${Platform.pathSeparator}list.m3u');
    await file.writeAsString(_playlist);

    // No fetch override: this exercises the real path-vs-URL branch.
    final source =
        M3uMediaSource(Account.m3u(name: 'Local', url: file.path));
    await source.validate(); // throws if the file couldn't be read/parsed
  });

  test('the default fetcher reads a file:// URI', () async {
    final file = File('${dir.path}${Platform.pathSeparator}list.m3u');
    await file.writeAsString(_playlist);

    final source = M3uMediaSource(
        Account.m3u(name: 'Local', url: file.uri.toString()));
    await source.validate();
  });

  test('a missing local file surfaces as an error, not a hang', () async {
    final source = M3uMediaSource(Account.m3u(
        name: 'Gone', url: '${dir.path}${Platform.pathSeparator}nope.m3u'));
    await expectLater(source.validate(), throwsA(isA<Exception>()));
  });
}
