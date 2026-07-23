import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/api/xtream_api_service.dart';

import '../support/test_support.dart';

/// A programmable Dio adapter: each request runs [handler], which returns the
/// canned [ResponseBody] to feed back (or a non-2xx status so Dio raises a
/// DioException, exercising the retry/error paths).
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);
  final ResponseBody Function(RequestOptions options, int callIndex) handler;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final index = calls++;
    return handler(options, index);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object data,
    {int status = 200, Map<String, List<String>>? extraHeaders}) {
  return ResponseBody.fromString(
    jsonEncode(data),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
      ...?extraHeaders,
    },
  );
}

XtreamApiService _serviceWith(_FakeAdapter adapter) {
  final dio = Dio()..httpClientAdapter = adapter;
  return XtreamApiService(dio: dio);
}

void main() {
  final account = accountNamed('api');

  setUpAll(() async {
    await initDbEnvironment(); // cached endpoints touch CatalogDatabase
  });

  group('authenticate', () {
    test('returns user_info on a successful login', () async {
      final service = _serviceWith(_FakeAdapter(
        (_, __) => _json({
          'user_info': {'auth': 1, 'username': 'api'}
        }),
      ));
      final info = await service.authenticate(account);
      expect(info['username'], 'api');
    });

    test('throws on auth == 0', () async {
      final service = _serviceWith(_FakeAdapter(
        (_, __) => _json({
          'user_info': {'auth': 0}
        }),
      ));
      expect(
        () => service.authenticate(account),
        throwsA(isA<XtreamApiException>().having(
            (e) => e.message, 'message', contains('Invalid username'))),
      );
    });

    test('throws when the shape is not an Xtream panel response', () async {
      final service = _serviceWith(_FakeAdapter((_, __) => _json({'foo': 'bar'})));
      expect(
        () => service.authenticate(account),
        throwsA(isA<XtreamApiException>()
            .having((e) => e.message, 'message', contains('Unexpected response'))),
      );
    });
  });

  group('getAccountStatus', () {
    test('parses the user_info block into an AccountStatus', () async {
      final service = _serviceWith(_FakeAdapter(
        (_, __) => _json({
          'user_info': {
            'status': 'Active',
            'exp_date': '1893456000',
            'is_trial': '0',
            'active_cons': '2',
            'max_connections': '2',
          },
          'server_info': {'time_now': '2026-01-01 00:00:00'},
        }),
      ));
      final status = await service.getAccountStatus(account);
      expect(status.status, 'Active');
      expect(status.activeConnections, 2);
      expect(status.maxConnections, 2);
      expect(status.atConnectionLimit, isTrue);
    });

    test('throws when the response has no user_info block', () async {
      final service = _serviceWith(_FakeAdapter((_, __) => _json({'foo': 'bar'})));
      await expectLater(
        () => service.getAccountStatus(account),
        throwsA(isA<XtreamApiException>()),
      );
    });
  });

  group('list endpoints', () {
    test('getLiveCategories parses a JSON array', () async {
      final service = _serviceWith(_FakeAdapter((_, __) => _json([
            {'category_id': '1', 'category_name': 'News'},
            {'category_id': 2, 'category_name': 'Sports'},
          ])));
      final cats = await service.getLiveCategories(account);
      expect(cats.map((c) => c.categoryId), ['1', '2']);
    });

    test('getLiveStreams throws on a non-list body', () async {
      final service =
          _serviceWith(_FakeAdapter((_, __) => _json({'not': 'a list'})));
      expect(
        () => service.getLiveStreams(account, '1'),
        throwsA(isA<XtreamApiException>()),
      );
    });

    test('getVodStreams parses movies', () async {
      final service = _serviceWith(_FakeAdapter((_, __) => _json([
            {'stream_id': 120, 'name': 'The Matrix', 'category_id': '4'},
          ])));
      final movies = await service.getVodStreams(account, '4');
      expect(movies.single.name, 'The Matrix');
    });
  });

  group('_get retry + error mapping', () {
    test('retries past a 429 (Retry-After: 0) then succeeds', () async {
      final adapter = _FakeAdapter((_, i) {
        if (i == 0) {
          return _json({}, status: 429, extraHeaders: {
            'retry-after': ['0']
          });
        }
        return _json([]); // valid empty category list
      });
      final service = _serviceWith(adapter);
      final cats = await service.getLiveCategories(account);
      expect(cats, isEmpty);
      expect(adapter.calls, 2);
    });

    test('maps an exhausted 429 to a rate-limited exception', () async {
      final adapter = _FakeAdapter((_, __) => _json({}, status: 429, extraHeaders: {
            'retry-after': ['0']
          }));
      final service = _serviceWith(adapter);
      try {
        await service.getLiveCategories(account);
        fail('expected an exception');
      } on XtreamApiException catch (e) {
        expect(e.isRateLimited, isTrue);
      }
      // Interactive default: fail fast (initial + 2 retries) rather than
      // keeping the user staring at a spinner through long 429 backoffs.
      expect(adapter.calls, 3);
    });

    test('background retry budget waits out more 429s than interactive', () async {
      final adapter = _FakeAdapter((_, __) => _json({}, status: 429, extraHeaders: {
            'retry-after': ['0']
          }));
      final service = _serviceWith(adapter);
      await expectLater(
        () => service.getLiveCategories(account,
            maxRetries: XtreamApiService.backgroundMaxRetries),
        throwsA(isA<XtreamApiException>()
            .having((e) => e.isRateLimited, 'isRateLimited', isTrue)),
      );
      expect(adapter.calls, XtreamApiService.backgroundMaxRetries + 1);
    });

    test('maps a non-retryable status to a friendly failure', () async {
      final adapter = _FakeAdapter((_, __) => _json({'e': 1}, status: 404));
      final service = _serviceWith(adapter);
      await expectLater(
        () => service.getLiveCategories(account),
        throwsA(isA<XtreamApiException>()
            .having((e) => e.message, 'message', contains('Request failed'))),
      );
      expect(adapter.calls, 1); // not retried
    });
  });

  group('sanitizeErrorMessage', () {
    test('redacts Xtream credentials embedded in a message', () {
      const message = 'The connection errored: uri: '
          'http://host:8080/player_api.php?username=alice&password=s3cret&action=x';
      final sanitized = XtreamApiService.sanitizeErrorMessage(message);
      expect(sanitized, isNot(contains('s3cret')));
      expect(sanitized, isNot(contains('alice')));
      expect(sanitized, contains('username=***'));
      expect(sanitized, contains('password=***'));
      expect(sanitized, contains('action=x')); // rest of the message intact
    });

    test('leaves credential-free messages untouched', () {
      const message = 'Connection to server timed out.';
      expect(XtreamApiService.sanitizeErrorMessage(message), message);
    });
  });

  group('caching', () {
    test('getShortEpg hits the network once, then serves from cache', () async {
      final epgAccount = accountNamed('api-epg-cache');
      final adapter = _FakeAdapter((_, __) => _json({
            'epg_listings': [
              {
                'title': base64.encode(utf8.encode('Now Playing')),
                'description': '',
                'start_timestamp': '1700000000',
                'stop_timestamp': '1700003600',
              }
            ]
          }));
      final service = _serviceWith(adapter);

      final first = await service.getShortEpg(epgAccount, 'chan-1');
      expect(first.single.title, 'Now Playing');

      final second = await service.getShortEpg(epgAccount, 'chan-1');
      expect(second.single.title, 'Now Playing');
      expect(adapter.calls, 1); // second call came from the disk cache
    });
  });
}
