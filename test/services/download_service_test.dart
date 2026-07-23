import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/models/download_item.dart';
import 'package:iptv_player/data/services/download_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/test_support.dart';

DownloadItem _item(String id,
        {String type = 'movie', Map<String, String>? headers}) =>
    DownloadItem(
      type: type,
      id: id,
      name: 'Item $id',
      categoryId: '4',
      containerExtension: 'mp4',
      remoteUrl: 'http://host/movie/u/p/$id.mp4',
      headers: headers,
      status: DownloadStatus.queued,
      addedAt: 1,
    );

/// A fake downloader that "writes" the file and reports progress, no network.
Future<void> _okDownloader(String url, String savePath,
    {required void Function(int, int) onProgress,
    required CancelToken token,
    Map<String, String>? headers}) async {
  onProgress(5, 10);
  await File(savePath).writeAsBytes(List<int>.filled(10, 1));
  onProgress(10, 10);
}

Future<void> _failDownloader(String url, String savePath,
    {required void Function(int, int) onProgress,
    required CancelToken token,
    Map<String, String>? headers}) async {
  throw DioException(
      requestOptions: RequestOptions(path: url),
      type: DioExceptionType.connectionError);
}

/// Blocks until the token is cancelled, then throws a cancel DioException —
/// lets a test deterministically cancel an "in-flight" download.
Future<void> _hangDownloader(String url, String savePath,
    {required void Function(int, int) onProgress,
    required CancelToken token,
    Map<String, String>? headers}) {
  final c = Completer<void>();
  token.whenCancel.then((_) => c.completeError(DioException(
      requestOptions: RequestOptions(path: url),
      type: DioExceptionType.cancel)));
  return c.future;
}

/// Waits (real time, bounded) until no download is still queued/downloading —
/// more reliable than pumpEventQueue, whose fixed iteration cap can give up
/// before several sequential transfers finish.
Future<void> _settle() async {
  for (var i = 0; i < 400; i++) {
    final pending = DownloadService.instance.items.where((it) =>
        it.status == DownloadStatus.queued ||
        it.status == DownloadStatus.downloading);
    if (pending.isEmpty) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  final service = DownloadService.instance;

  setUp(() async {
    await initDbEnvironment(); // gives getApplicationSupportDirectory a temp dir
    SharedPreferences.setMockInitialValues({});
    await service.resetForTesting();
    service.downloaderForTesting = _okDownloader;
  });

  test('enqueue downloads to completion and writes the file', () async {
    final account = accountNamed('dl-ok');
    await service.loadFor(account);
    final item = _item('1');
    await service.enqueue(item);
    await _settle();

    expect(service.isDownloaded('movie', '1'), isTrue);
    expect(service.statusFor('1'), DownloadStatus.completed);
    expect(await File(service.localPathFor(item)!).exists(), isTrue);
  });

  test("the item's headers reach the downloader (M3U default UA)", () async {
    Map<String, String>? seen;
    service.downloaderForTesting = (url, savePath,
        {required onProgress,
        required token,
        Map<String, String>? headers}) async {
      seen = headers;
      await File(savePath).writeAsBytes(List<int>.filled(3, 1));
    };
    await service.loadFor(accountNamed('dl-headers'));
    await service.enqueue(
        _item('1', headers: {'User-Agent': 'Mozilla/5.0 test'}));
    await _settle();
    expect(seen, {'User-Agent': 'Mozilla/5.0 test'});
  });

  test('does not enqueue the same item twice', () async {
    await service.loadFor(accountNamed('dl-dupe'));
    await service.enqueue(_item('1'));
    await service.enqueue(_item('1'));
    await _settle();
    expect(service.items.where((i) => i.id == '1'), hasLength(1));
  });

  test('a failed transfer is marked failed and leaves no file', () async {
    service.downloaderForTesting = _failDownloader;
    final account = accountNamed('dl-fail');
    await service.loadFor(account);
    final item = _item('1');
    await service.enqueue(item);
    await _settle();

    expect(service.statusFor('1'), DownloadStatus.failed);
    expect(service.isDownloaded('movie', '1'), isFalse);
    expect(await File(service.localPathFor(item)!).exists(), isFalse);
  });

  test('retry re-runs a failed download to completion', () async {
    service.downloaderForTesting = _failDownloader;
    await service.loadFor(accountNamed('dl-retry'));
    await service.enqueue(_item('1'));
    await _settle();
    expect(service.statusFor('1'), DownloadStatus.failed);

    service.downloaderForTesting = _okDownloader;
    await service.retry('1');
    await _settle();
    expect(service.statusFor('1'), DownloadStatus.completed);
  });

  test('cancel aborts an in-flight download and discards it', () async {
    service.downloaderForTesting = _hangDownloader;
    final account = accountNamed('dl-cancel');
    await service.loadFor(account);
    final item = _item('1');
    await service.enqueue(item);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(service.statusFor('1'), DownloadStatus.downloading);

    await service.cancel('1');
    await _settle();
    expect(service.statusFor('1'), isNull); // removed
    expect(await File(service.localPathFor(item)!).exists(), isFalse);
  });

  test('deleteDownload removes a completed item and its file', () async {
    final account = accountNamed('dl-delete');
    await service.loadFor(account);
    final item = _item('1');
    await service.enqueue(item);
    await _settle();
    final path = service.localPathFor(item)!;
    expect(await File(path).exists(), isTrue);

    await service.deleteDownload('1');
    expect(service.statusFor('1'), isNull);
    expect(await File(path).exists(), isFalse);
  });

  test('loadFor flips a stale downloading/queued item to failed', () async {
    final account = accountNamed('dl-stale');
    final stale = _item('7').copyWith(status: DownloadStatus.downloading);
    SharedPreferences.setMockInitialValues({
      'downloads_v1_${account.key}': [jsonEncode(stale.toJson())],
    });
    await service.loadFor(account);
    expect(service.statusFor('7'), DownloadStatus.failed);
  });

  test('runs one download at a time (queue stays sequential)', () async {
    var maxConcurrent = 0;
    var active = 0;
    service.downloaderForTesting = (url, savePath,
        {required onProgress, required token, Map<String, String>? headers}) async {
      active++;
      maxConcurrent = active > maxConcurrent ? active : maxConcurrent;
      await File(savePath).writeAsBytes([1]);
      active--;
    };
    await service.loadFor(accountNamed('dl-seq'));
    await service.enqueue(_item('1'));
    await service.enqueue(_item('2'));
    await service.enqueue(_item('3'));
    await _settle();
    expect(maxConcurrent, 1);
    expect(service.items.where((i) => i.status == DownloadStatus.completed),
        hasLength(3));
  });

  test('a failed transfer keeps its partial file so a retry can resume',
      () async {
    // First attempt writes 5 bytes, then fails — the partial must survive.
    service.downloaderForTesting = (url, savePath,
        {required onProgress, required token, Map<String, String>? headers}) async {
      await File(savePath).writeAsBytes(List<int>.filled(5, 1));
      throw DioException(
          requestOptions: RequestOptions(path: url),
          type: DioExceptionType.connectionError);
    };
    final account = accountNamed('dl-resume');
    await service.loadFor(account);
    final item = _item('1');
    await service.enqueue(item);
    await _settle();

    expect(service.statusFor('1'), DownloadStatus.failed);
    final file = File(service.localPathFor(item)!);
    expect(await file.exists(), isTrue);
    expect(await file.length(), 5, reason: 'partial kept, not deleted');

    // Retry: resume from the 5 bytes on disk and append the rest.
    service.downloaderForTesting = (url, savePath,
        {required onProgress, required token, Map<String, String>? headers}) async {
      final have = await File(savePath).length();
      expect(have, 5, reason: 'resume point is the surviving partial');
      await File(savePath)
          .writeAsBytes(List<int>.filled(5, 2), mode: FileMode.append);
    };
    await service.retry('1');
    await _settle();

    expect(service.statusFor('1'), DownloadStatus.completed);
    expect(await file.length(), 10, reason: 'resumed rather than restarted');
  });

  test('runs up to maxConcurrent transfers in parallel', () async {
    var active = 0;
    var maxActive = 0;
    final gate = Completer<void>();
    service.downloaderForTesting = (url, savePath,
        {required onProgress, required token, Map<String, String>? headers}) async {
      active++;
      maxActive = active > maxActive ? active : maxActive;
      await gate.future; // hold every transfer open until released
      await File(savePath).writeAsBytes([1]);
      active--;
    };
    await service.loadFor(accountNamed('dl-parallel'));
    await service.setMaxConcurrent(3);
    for (final id in ['1', '2', '3', '4']) {
      await service.enqueue(_item(id));
    }
    // Let the pump start as many as the limit allows.
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(maxActive, 3, reason: '3 run at once, the 4th waits its turn');

    gate.complete();
    await _settle();
    expect(maxActive, 3, reason: 'the freed slot never exceeded the limit');
    expect(service.items.where((i) => i.status == DownloadStatus.completed),
        hasLength(4));
  });

  test('setMaxConcurrent persists and clamps to 1..4', () async {
    await service.loadFor(accountNamed('dl-concurrency'));
    await service.setMaxConcurrent(9);
    expect(service.maxConcurrent, 4);
    await service.setMaxConcurrent(0);
    expect(service.maxConcurrent, 1);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('downloads_max_concurrent_v1'), 1);
  });

  test('setBandwidthLimitKbps persists (0 = unlimited)', () async {
    await service.loadFor(accountNamed('dl-bandwidth'));
    await service.setBandwidthLimitKbps(2048);
    expect(service.bandwidthLimitKbps, 2048);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('downloads_bandwidth_kbps_v1'), 2048);
    await service.setBandwidthLimitKbps(0);
    expect(service.bandwidthLimitKbps, 0);
  });

  group('DownloadRateLimiter', () {
    test('never waits when unlimited', () {
      final rl = DownloadRateLimiter(0);
      expect(rl.reserve(1 << 20), Duration.zero);
    });

    test('paces to the rate once the burst budget is spent', () {
      var now = 0;
      final rl = DownloadRateLimiter(1000, nowMicros: () => now); // 1000 B/s
      expect(rl.reserve(1000), Duration.zero); // one second's burst up-front
      expect(rl.reserve(500).inMilliseconds, closeTo(500, 5));
    });

    test('elapsed time refills the budget', () {
      var now = 0;
      final rl = DownloadRateLimiter(1000, nowMicros: () => now);
      rl.reserve(1000); // spend the burst
      now += 500000; // half a second later -> 500 more bytes allowed
      expect(rl.reserve(500), Duration.zero);
    });
  });

  test('switching accounts cancels in-flight transfers but keeps partials',
      () async {
    // Writes a 5-byte partial, then hangs until cancelled — rethrowing the
    // token's own cancel exception, like real dio, so the service can tell an
    // account-switch cancel (keep the partial) from a user cancel (delete it).
    final started = Completer<void>();
    service.downloaderForTesting = (url, savePath,
        {required onProgress, required token, Map<String, String>? headers}) async {
      await File(savePath).writeAsBytes(List<int>.filled(5, 1));
      if (!started.isCompleted) started.complete();
      final c = Completer<void>();
      unawaited(token.whenCancel.then(c.completeError));
      return c.future;
    };
    final a = accountNamed('dl-switch-a');
    await service.loadFor(a);
    final inFlight = _item('1');
    await service.enqueue(inFlight);
    await service.enqueue(_item('2')); // waits its turn in the queue
    await started.future;
    final partialPath = service.localPathFor(inFlight)!;

    await service.loadFor(accountNamed('dl-switch-b'));
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(service.items, isEmpty,
        reason: "the new account must not inherit the old account's transfers");
    expect(await File(partialPath).exists(), isTrue,
        reason: 'a switch keeps the partial so switching back can resume');

    // Switching back: both items come off disk as failed (resumable), not
    // stuck forever in queued/downloading.
    await service.loadFor(a);
    expect(service.statusFor('1'), DownloadStatus.failed);
    expect(service.statusFor('2'), DownloadStatus.failed);
  });

  test('deleting a download removes its resume sidecar too', () async {
    final account = accountNamed('dl-sidecar');
    await service.loadFor(account);
    final item = _item('1');
    await service.enqueue(item);
    await _settle();
    final path = service.localPathFor(item)!;
    await File('$path.dlmeta').writeAsString('"etag-123"');

    await service.deleteDownload('1');
    expect(File(path).existsSync(), isFalse);
    expect(File('$path.dlmeta').existsSync(), isFalse,
        reason: 'the If-Range validator must not outlive its file');
  });

  test('deleteFor wipes an account\'s downloads and metadata', () async {
    final account = accountNamed('dl-wipe');
    await service.loadFor(account);
    final item = _item('1');
    await service.enqueue(item);
    await _settle();
    final path = service.localPathFor(item)!;

    await service.deleteFor(account);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('downloads_v1_${account.key}'), isNull);
    expect(await File(path).exists(), isFalse);
  });
}
