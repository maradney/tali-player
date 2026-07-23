import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/api/credential_redaction.dart';
import 'package:iptv_player/data/models/channel.dart';
import 'package:iptv_player/data/models/movie.dart';

void main() {
  group('redactCredentials', () {
    test('redacts credentials in a player_api.php query string', () {
      const message = 'The connection errored: uri: '
          'http://host:8080/player_api.php?username=alice&password=s3cret&action=x';
      final out = redactCredentials(message);
      expect(out, isNot(contains('alice')));
      expect(out, isNot(contains('s3cret')));
      expect(out, contains('username=***'));
      expect(out, contains('password=***'));
      expect(out, contains('action=x')); // rest of the message survives
    });

    test('redacts credentials in the path of every stream URL we build', () {
      // Built the same way the app builds them, so a change to a URL format
      // that outruns the redaction shows up here.
      const channel = Channel(streamId: '123', name: 'Ch', categoryId: '1');
      const movie = Movie(
          streamId: '55',
          name: 'M',
          categoryId: '2',
          containerExtension: 'mkv');
      final urls = <String>[
        channel.streamUrl(
            serverUrl: 'http://host:8080', username: 'alice', password: 's3cret'),
        movie.streamUrl(
            serverUrl: 'http://host:8080', username: 'alice', password: 's3cret'),
        'http://host:8080/series/alice/s3cret/900.mkv',
        'http://host:8080/timeshift/alice/s3cret/60/2026-08-03:20-00/123.ts',
      ];

      for (final url in urls) {
        final out = redactCredentials('Failed to open $url.');
        expect(out, isNot(contains('alice')), reason: url);
        expect(out, isNot(contains('s3cret')), reason: url);
        expect(out, contains('***'), reason: url);
        // The host stays, so the message still says something useful.
        expect(out, contains('host:8080'), reason: url);
      }
    });

    test('leaves credential-free text untouched', () {
      const message = 'Connection to server timed out.';
      expect(redactCredentials(message), message);
    });
  });
}
