import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:iptv_player/features/common/poster_cache_repair.dart';

/// A poster cached in an unusable state stays broken for seven days, because
/// flutter_cache_manager stores any 200/202 body without checking it decodes
/// and then serves it from disk without refetching. These cover the policy
/// that gets it re-fetched exactly once instead.
void main() {
  late List<String> disk;
  late List<String> memory;

  PosterCacheRepair make({int max = 512}) => PosterCacheRepair(
        removeFromDisk: (u) async => disk.add(u),
        evictFromMemory: (u) async => memory.add(u),
        maxRemembered: max,
      );

  setUp(() {
    disk = [];
    memory = [];
  });

  const url = 'https://cdn.example.com/poster.jpg';

  group('isWorthRetrying', () {
    test('a decode failure is worth retrying', () {
      // The case this whole class exists for: bytes were cached, and they are
      // not an image.
      expect(PosterCacheRepair.isWorthRetrying(Exception('bad image data')),
          isTrue);
      expect(
          PosterCacheRepair.isWorthRetrying(const FileSystemException('boom')),
          isTrue);
    });

    test('an HTTP status failure is not', () {
      // A non-200/202 never reaches _saveFile, so nothing was cached and there
      // is nothing to repair - retrying would only re-ask for a URL the server
      // already refused.
      for (final code in [403, 404, 429, 500]) {
        expect(
          PosterCacheRepair.isWorthRetrying(
              HttpExceptionWithStatus(code, 'Invalid statusCode: $code')),
          isFalse,
          reason: 'status $code should not trigger a refetch',
        );
      }
    });
  });

  test('repairs a URL once, then refuses', () async {
    final repair = make();

    expect(await repair.repairOnce(url, Exception('bad image data')), isTrue);
    expect(disk, [url]);
    expect(memory, [url]);

    // A grid of broken posters rebuilds constantly while scrolling; without
    // this cap each rebuild would be a fresh download.
    expect(await repair.repairOnce(url, Exception('bad image data')), isFalse);
    expect(await repair.repairOnce(url, Exception('bad image data')), isFalse);
    expect(disk, hasLength(1));
    expect(memory, hasLength(1));
  });

  test('drops both caches, not just the disk one', () async {
    // Evicting only the disk entry leaves Flutter's ImageCache holding the
    // decoded failure, so the retry would show the same broken image.
    final repair = make();
    await repair.repairOnce(url, Exception('bad image data'));
    expect(disk.single, url);
    expect(memory.single, url);
  });

  test('an HTTP failure touches neither cache', () async {
    final repair = make();
    final ok = await repair.repairOnce(
        url, HttpExceptionWithStatus(404, 'Invalid statusCode: 404'));
    expect(ok, isFalse);
    expect(disk, isEmpty);
    expect(memory, isEmpty);
    // It must also stay eligible: a 404 today can be a live poster tomorrow.
    expect(await repair.repairOnce(url, Exception('bad image data')), isTrue);
  });

  test('different URLs are independent', () async {
    final repair = make();
    expect(await repair.repairOnce('$url?a', Exception('x')), isTrue);
    expect(await repair.repairOnce('$url?b', Exception('x')), isTrue);
    expect(disk, ['$url?a', '$url?b']);
  });

  test('what it remembers is bounded, forgetting oldest first', () async {
    // A large catalog can push tens of thousands of poster URLs through here
    // in one session; the set must not grow without limit.
    final repair = make(max: 3);
    for (var i = 0; i < 5; i++) {
      expect(await repair.repairOnce('$url?$i', Exception('x')), isTrue);
    }
    expect(repair.rememberedCount, lessThanOrEqualTo(3));

    // The oldest was forgotten, so it becomes eligible once more - deliberate,
    // and better than either leaking memory or never healing again.
    expect(await repair.repairOnce('$url?0', Exception('x')), isTrue);
    // The newest is still remembered and still refused.
    expect(await repair.repairOnce('$url?4', Exception('x')), isFalse);
  });

  test('forgetAll makes everything eligible again', () async {
    // Clearing the image cache by hand removes the files the guard was
    // protecting, so the guard has to reset with it.
    final repair = make();
    expect(await repair.repairOnce(url, Exception('x')), isTrue);
    expect(await repair.repairOnce(url, Exception('x')), isFalse);

    repair.forgetAll();
    expect(repair.rememberedCount, 0);
    expect(await repair.repairOnce(url, Exception('x')), isTrue);
  });
}
