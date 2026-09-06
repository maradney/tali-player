import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/services/single_instance.dart';

/// Keeping one copy of the app per user.
///
/// Read this before trusting the coverage: the actual exclusion — a second
/// *process* being refused the lock — cannot be exercised here. File locks are
/// held per process, so a second claim() from this same test would succeed and
/// prove nothing. Only running two builds does that.
///
/// What is testable, and what these cover, is everything around it: that the
/// lock and request files land where expected, that a request is picked up and
/// consumed exactly once, that a stale request is swept at startup, and above
/// all that a broken environment yields "unknown" rather than an exception —
/// because callers treat anything but a definite refusal as permission to
/// start, and an app that will not open is far worse than one that opens twice.
void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('single_instance_test_');
  });

  tearDown(() async {
    await SingleInstance.instance.release();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  File lockFile() => File('${dir.path}${Platform.pathSeparator}'
      '${SingleInstance.lockFileName}');
  File requestFile() => File('${dir.path}${Platform.pathSeparator}'
      '${SingleInstance.showRequestFileName}');

  test('the first claim wins and creates the lock file', () async {
    final role = await SingleInstance.instance.claim(dir);
    expect(role, InstanceRole.primary);
    expect(lockFile().existsSync(), isTrue);
  });

  test('the locked file is still held afterwards', () async {
    // Not the formality it looks. The open file has to stay *reachable* for
    // the life of the process: dart:io closes a RandomAccessFile from a
    // finalizer once nothing refers to it, and closing it releases the lock.
    //
    // The first version stored it in a field that nothing ever read, which
    // AOT correctly treated as dead and optimised away - so release builds
    // took the lock, dropped it moments later, and every launch believed it
    // was the first. JIT kept the store, so tests and  passed while
    // the shipped app did not.
    //
    // This assertion is also the read that keeps the reference alive. If it
    // ever looks redundant, that is exactly the bug coming back.
    await SingleInstance.instance.claim(dir);
    expect(SingleInstance.instance.holdsLock, isTrue);

    await SingleInstance.instance.release();
    expect(SingleInstance.instance.holdsLock, isFalse);
  });

  test('a missing directory is created rather than failing the launch',
      () async {
    final nested = Directory('${dir.path}${Platform.pathSeparator}a'
        '${Platform.pathSeparator}b');
    expect(nested.existsSync(), isFalse);

    final role = await SingleInstance.instance.claim(nested);
    expect(role, InstanceRole.primary);
    expect(nested.existsSync(), isTrue);
  });

  test('an unusable location reports unknown, never secondary', () async {
    // The property that matters most. A caller treats unknown as "carry on and
    // start"; returning secondary here would mean an app that silently exits
    // on every launch, with no window and no message.
    final impossible = Directory(
        '${dir.path}${Platform.pathSeparator}${'x' * 400}'
        '${Platform.pathSeparator}${'y' * 400}');

    final role = await SingleInstance.instance.claim(impossible);
    expect(role, isNot(InstanceRole.secondary));
  });

  test('a show request is picked up and consumed once', () async {
    await SingleInstance.instance.claim(dir);
    var shown = 0;
    SingleInstance.instance.listenForShowRequests(() => shown++);

    await SingleInstance.requestShowFor(dir);
    expect(requestFile().existsSync(), isTrue);

    // The poll is once a second; give it room.
    await Future<void>.delayed(SingleInstance.pollInterval * 2);

    expect(shown, 1, reason: 'the request should fire the callback');
    expect(requestFile().existsSync(), isFalse,
        reason: 'and be deleted, so it does not fire again every second');

    await Future<void>.delayed(SingleInstance.pollInterval * 2);
    expect(shown, 1, reason: 'still exactly once');
  });

  test('a request written before listening starts is not lost', () async {
    // The race: a second process can write its request between claim()
    // returning and the listener starting. It has already exited by then and
    // will not ask again, so the request has to survive the gap.
    await SingleInstance.instance.claim(dir);
    await SingleInstance.requestShowFor(dir);

    var shown = 0;
    SingleInstance.instance.listenForShowRequests(() => shown++);
    await Future<void>.delayed(Duration.zero);

    expect(shown, 1);
  });

  test('a request orphaned by a dead instance is swept on startup', () async {
    // Left behind by a copy that was killed before reading it. Without the
    // sweep the next launch would raise its own window for no reason.
    await SingleInstance.requestShowFor(dir);
    expect(requestFile().existsSync(), isTrue);

    await SingleInstance.instance.claim(dir);
    expect(requestFile().existsSync(), isFalse);
  });

  test('releasing lets a later claim succeed again', () async {
    expect(await SingleInstance.instance.claim(dir), InstanceRole.primary);
    await SingleInstance.instance.release();
    expect(await SingleInstance.instance.claim(dir), InstanceRole.primary);
  });
}
