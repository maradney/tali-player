import 'dart:async';
import 'dart:io';

/// Whether this process should own the window.
enum InstanceRole {
  /// First in. Holds the lock and runs normally.
  primary,

  /// Another instance already holds the lock. This one has asked it to show
  /// itself and should exit without building any UI.
  secondary,

  /// The check could not be completed. Deliberately treated as [primary] by
  /// callers — see [claim].
  unknown,
}

/// Keeps one copy of the app running per user.
///
/// With "keep running in the tray" on, closing the window only hides it, so
/// launching again started a second copy and left the first one hidden in the
/// notification area. Three launches, three tray icons, and no obvious way to
/// tell which window belonged to which.
///
/// The mechanism is an exclusive lock on a file in the app's own support
/// directory, plus a small request file for "the user tried to open me again,
/// come to the front". A lock rather than a recorded process id on purpose:
/// the operating system drops the lock when the process ends, *including*
/// when it is killed or crashes, so there is no stale state to strand the
/// next launch. A pid file has exactly that failure and it is a nasty one —
/// the app stops starting and nothing says why.
///
/// Per user, not per machine: the support directory is per user account, so
/// two people on the same PC each get their own instance, which is right.
class SingleInstance {
  SingleInstance._();
  static final SingleInstance instance = SingleInstance._();

  static const lockFileName = 'instance.lock';
  static const showRequestFileName = 'show.request';

  /// Polled rather than watched. Directory watchers on Windows miss events
  /// and fire duplicates; a one-second poll of a single file costs nothing and
  /// behaves the same everywhere.
  static const pollInterval = Duration(seconds: 1);

  RandomAccessFile? _lock;
  Timer? _poll;
  Directory? _dir;

  /// Tries to become the primary instance.
  ///
  /// Returns [InstanceRole.unknown] rather than throwing if anything goes
  /// wrong. Callers must treat that as "carry on and start": failing to work
  /// out whether another copy is running is a far smaller problem than an app
  /// that refuses to open because its lock file lives somewhere awkward.
  Future<InstanceRole> claim(Directory dir) async {
    try {
      if (!dir.existsSync()) dir.createSync(recursive: true);
      _dir = dir;
      final raf = await File(_pathTo(dir, lockFileName)).open(
        mode: FileMode.write,
      );
      try {
        // Non-blocking: FileLock.exclusive fails rather than waiting, which is
        // what makes this a test for "is another copy running" instead of a
        // way to hang behind one.
        await raf.lock(FileLock.exclusive);
      } on FileSystemException {
        await raf.close();
        await _writeShowRequest(dir);
        return InstanceRole.secondary;
      }
      _lock = raf;
      // A request left by an instance that died before reading it would
      // otherwise make this one raise its window for no reason.
      clearShowRequest(dir);
      return InstanceRole.primary;
    } catch (_) {
      return InstanceRole.unknown;
    }
  }

  /// Starts watching for another launch asking this instance to show itself.
  ///
  /// Checks once immediately: a second process can write its request in the
  /// gap between [claim] returning and this being called, and a request that
  /// arrives in that window must not be lost — the process that wrote it has
  /// already exited and will not ask again.
  void listenForShowRequests(void Function() onShowRequested) {
    final dir = _dir;
    if (dir == null) return;
    _poll?.cancel();
    _consume(dir, onShowRequested);
    _poll = Timer.periodic(
      pollInterval,
      (_) => _consume(dir, onShowRequested),
    );
  }

  void _consume(Directory dir, void Function() onShowRequested) {
    try {
      final file = File(_pathTo(dir, showRequestFileName));
      if (!file.existsSync()) return;
      file.deleteSync();
      onShowRequested();
    } catch (_) {
      // A transient read error just means we try again in a second.
    }
  }

  Future<void> _writeShowRequest(Directory dir) async {
    try {
      await File(_pathTo(dir, showRequestFileName)).writeAsString(
        DateTime.now().toIso8601String(),
        flush: true,
      );
    } catch (_) {
      // Best effort. Worst case the running copy stays in the tray and this
      // one still exits, which is the more important half of the job.
    }
  }

  /// Removes any pending request. Exposed for the startup sweep and tests.
  static void clearShowRequest(Directory dir) {
    try {
      final file = File(_pathTo(dir, showRequestFileName));
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
  }

  /// Writes a request without holding any lock. Exposed for tests; the real
  /// path goes through [claim].
  static Future<void> requestShowFor(Directory dir) =>
      instance._writeShowRequest(dir);

  static String _pathTo(Directory dir, String name) =>
      '${dir.path}${Platform.pathSeparator}$name';

  Future<void> release() async {
    _poll?.cancel();
    _poll = null;
    try {
      await _lock?.unlock();
      await _lock?.close();
    } catch (_) {}
    _lock = null;
  }
}
