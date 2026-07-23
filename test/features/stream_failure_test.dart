import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/features/player/stream_failure.dart';

void main() {
  group('classifyStreamFailure', () {
    test('401/403 are treated as blocked', () {
      expect(classifyStreamFailure(statusCode: 403), StreamFailureKind.blocked);
      expect(classifyStreamFailure(statusCode: 401), StreamFailureKind.blocked);
    });

    test('a Cloudflare challenge body is blocked, whatever the status', () {
      const body = '<!DOCTYPE html><title>Just a moment...</title>';
      expect(classifyStreamFailure(statusCode: 503, bodySnippet: body),
          StreamFailureKind.blocked);
      // Some challenges even come back 200.
      expect(classifyStreamFailure(statusCode: 200, bodySnippet: body),
          StreamFailureKind.blocked);
    });

    test('other anti-bot markers are blocked', () {
      expect(
          classifyStreamFailure(
              statusCode: 200, bodySnippet: 'window.challenge-platform'),
          StreamFailureKind.blocked);
      expect(
          classifyStreamFailure(
              statusCode: 403, bodySnippet: 'Attention Required! | Cloudflare'),
          StreamFailureKind.blocked);
    });

    test('404/410 are not found', () {
      expect(classifyStreamFailure(statusCode: 404), StreamFailureKind.notFound);
      expect(classifyStreamFailure(statusCode: 410), StreamFailureKind.notFound);
    });

    test('no status (never got a response) is unreachable', () {
      expect(classifyStreamFailure(statusCode: null),
          StreamFailureKind.unreachable);
    });

    test('a plain 200 with no challenge markers is unknown', () {
      expect(classifyStreamFailure(statusCode: 200, bodySnippet: '#EXTM3U'),
          StreamFailureKind.unknown);
    });
  });
}
