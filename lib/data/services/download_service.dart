import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/account.dart';
import '../models/download_item.dart';

/// How the service fetches a URL to a file. Injectable so tests can supply a
/// fake that reports progress and completes/fails without touching the network.
typedef Downloader = Future<void> Function(
  String url,
  String savePath, {
  required void Function(int received, int total) onProgress,
  required CancelToken token,
  Map<String, String>? headers,
});

/// Manages offline VOD downloads for the active account: a sequential queue,
/// on-disk files under the app-support directory, and persisted metadata.
/// Singleton + ChangeNotifier like the other per-account services
/// (Favorites/Watchlist), so screens listen via AnimatedBuilder.
///
/// Concurrency is deliberately 1 — one transfer at a time keeps disk and the
/// provider (429s) happy, and keeps the queue easy to reason about.
class DownloadService extends ChangeNotifier {
  DownloadService._();
  static final DownloadService instance = DownloadService._();

  static String _prefsKeyFor(String accountKey) => 'downloads_v1_$accountKey';

  /// A filesystem-safe, collision-free directory segment for an account — a
  /// short SHA-256 of its key (which contains '|', '://', etc.).
  static String _segmentFor(String accountKey) =>
      sha256.convert(utf8.encode(accountKey)).toString().substring(0, 16);

  final Dio _dio = Dio();
  Downloader? _downloaderOverride;
  Downloader get _downloader => _downloaderOverride ?? _dioDownload;

  /// Shared across every concurrent transfer, so the configured speed limit
  /// caps the *total* download bandwidth rather than each transfer separately.
  /// 0 bytes/sec means unlimited.
  final DownloadRateLimiter _rateLimiter = DownloadRateLimiter(0);

  /// Streams [url] to [savePath] by hand (rather than [Dio.download]) so we can
  /// (a) resume a partially-fetched file with an HTTP Range request and
  /// (b) pace writes through the shared [_rateLimiter] for the speed limit.
  ///
  /// If a partial file already exists we ask for `bytes=<size>-` and append;
  /// a server that ignores the Range (answers 200 instead of 206) makes us
  /// restart from scratch, which is correct — the bytes we have may not line up.
  ///
  /// When the first response carried a validator (ETag/Last-Modified) it's kept
  /// in a sidecar file and sent back as `If-Range` on resume, so a server whose
  /// file changed in between answers 200 (full restart) instead of splicing the
  /// tail of a *different* file onto our partial.
  Future<void> _dioDownload(
    String url,
    String savePath, {
    required void Function(int received, int total) onProgress,
    required CancelToken token,
    Map<String, String>? headers,
  }) async {
    final file = File(savePath);
    var startByte = 0;
    if (await file.exists()) startByte = await file.length();
    final validator = startByte > 0 ? await _readValidator(savePath) : null;

    // The item's own headers (M3U's default User-Agent) plus, on resume, the
    // Range/If-Range pair.
    final requestHeaders = <String, String>{
      ...?headers,
      if (startByte > 0) ...{
        'range': 'bytes=$startByte-',
        if (validator != null) 'if-range': validator,
      },
    };
    final response = await _dio.get<ResponseBody>(
      url,
      cancelToken: token,
      options: Options(
        responseType: ResponseType.stream,
        headers: requestHeaders.isEmpty ? null : requestHeaders,
      ),
    );

    // 206 = the server honoured our Range and is sending the tail; anything
    // else (typically 200) means it's sending the whole file, so ignore the
    // partial and overwrite.
    final resuming = startByte > 0 && response.statusCode == 206;
    final baseBytes = resuming ? startByte : 0;

    // A full (200) response defines the file's identity: remember its
    // validator for the next resume, or clear a stale one if it has none.
    if (!resuming) {
      await _writeValidator(
        savePath,
        response.headers.value('etag') ??
            response.headers.value('last-modified'),
      );
    }

    final remaining = int.tryParse(
            response.headers.value(Headers.contentLengthHeader) ?? '') ??
        -1;
    final total = remaining >= 0 ? baseBytes + remaining : -1;

    final sink =
        file.openWrite(mode: resuming ? FileMode.writeOnlyAppend : FileMode.writeOnly);
    var received = baseBytes;
    try {
      await for (final chunk in response.data!.stream) {
        final wait = _rateLimiter.reserve(chunk.length);
        if (wait > Duration.zero) await Future<void>.delayed(wait);
        sink.add(chunk);
        received += chunk.length;
        onProgress(received, total < 0 ? received : total);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    await _writeValidator(savePath, null); // complete — no more resumes
  }

  /// Where a download's resume validator lives, next to its partial file.
  static String _validatorPath(String savePath) => '$savePath.dlmeta';

  static Future<String?> _readValidator(String savePath) async {
    try {
      final f = File(_validatorPath(savePath));
      if (!await f.exists()) return null;
      final v = (await f.readAsString()).trim();
      return v.isEmpty ? null : v;
    } catch (_) {
      return null; // unreadable sidecar → resume without If-Range, as before
    }
  }

  /// Writes (or, for null, removes) the sidecar. Best-effort — losing the
  /// validator only degrades a future resume to the pre-If-Range behavior.
  static Future<void> _writeValidator(String savePath, String? validator) async {
    try {
      final f = File(_validatorPath(savePath));
      if (validator == null) {
        if (await f.exists()) await f.delete();
      } else {
        await f.writeAsString(validator);
      }
    } catch (_) {}
  }

  List<DownloadItem> _items = [];
  String? _loadedAccountKey;
  String? _dirPath; // resolved downloads dir for the loaded account

  // Live byte progress per id (not persisted); notifications are throttled.
  final Map<String, ({int received, int total})> _progress = {};
  DateTime _lastProgressNotify = DateTime.fromMillisecondsSinceEpoch(0);

  final List<String> _queue = []; // ids waiting to download
  final Map<String, CancelToken> _active = {}; // id -> cancel token, in flight

  // Global (not per-account) transfer settings, persisted under the keys below.
  static const _maxConcurrentKey = 'downloads_max_concurrent_v1';
  static const _bandwidthKey = 'downloads_bandwidth_kbps_v1';
  bool _settingsLoaded = false;

  int _maxConcurrent = 1; // 1..4 simultaneous transfers
  int _bandwidthLimitKbps = 0; // 0 = unlimited

  /// How many transfers may run at once (1–4). Default 1 stays gentle on the
  /// provider (429s) — raising it trades that for speed.
  int get maxConcurrent => _maxConcurrent;

  /// Combined speed cap across all active transfers, in KB/s. 0 = unlimited.
  int get bandwidthLimitKbps => _bandwidthLimitKbps;

  /// Newest-queued first.
  List<DownloadItem> get items =>
      List.unmodifiable(_items.reversed.toList());

  DownloadItem? _byId(String id) {
    for (final i in _items) {
      if (i.id == id) return i;
    }
    return null;
  }

  DownloadStatus? statusFor(String id) => _byId(id)?.status;

  bool isDownloaded(String type, String id) =>
      _items.any((i) => i.id == id && i.type == type &&
          i.status == DownloadStatus.completed);

  /// Byte progress for an active download as a 0..1 fraction, or null when it's
  /// not downloading or the server didn't report a size.
  double? progressFraction(String id) {
    final pr = _progress[id];
    if (pr == null || pr.total <= 0) return null;
    return (pr.received / pr.total).clamp(0.0, 1.0);
  }

  /// Absolute on-disk path for [item]'s file (valid after [loadFor]).
  String? localPathFor(DownloadItem item) =>
      _dirPath == null ? null : p.join(_dirPath!, item.fileName);

  /// Reads the global transfer settings once (they're not per-account).
  Future<void> _ensureSettingsLoaded() async {
    if (_settingsLoaded) return;
    _settingsLoaded = true;
    final prefs = await SharedPreferences.getInstance();
    _maxConcurrent = (prefs.getInt(_maxConcurrentKey) ?? 1).clamp(1, 4);
    _bandwidthLimitKbps = prefs.getInt(_bandwidthKey) ?? 0;
    _rateLimiter.bytesPerSecond = _bandwidthLimitKbps * 1024;
  }

  /// Raises/lowers how many transfers run at once (clamped to 1–4). Raising it
  /// immediately fills the freed slots from the queue.
  Future<void> setMaxConcurrent(int n) async {
    await _ensureSettingsLoaded();
    n = n.clamp(1, 4);
    if (n == _maxConcurrent) return;
    _maxConcurrent = n;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_maxConcurrentKey, n);
    unawaited(_pump());
  }

  /// Sets the combined speed cap in KB/s (0 = unlimited). Applies to transfers
  /// already in flight too, since the limiter is shared.
  Future<void> setBandwidthLimitKbps(int kbps) async {
    await _ensureSettingsLoaded();
    if (kbps < 0) kbps = 0;
    if (kbps == _bandwidthLimitKbps) return;
    _bandwidthLimitKbps = kbps;
    _rateLimiter.bytesPerSecond = kbps * 1024;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_bandwidthKey, kbps);
  }

  /// Cancel reason for an account switch — unlike a user cancel, the partial
  /// file must survive so switching back can resume it.
  static const _switchCancelReason = 'account switched';

  Future<void> loadFor(Account account) async {
    await _ensureSettingsLoaded();
    if (_loadedAccountKey == account.key) return;
    // Stop the previous account's transfers: their slots and bandwidth belong
    // to the new account now. Their items were last persisted as
    // queued/downloading, so the kill-recovery below flips them to failed on
    // the way back in, and the kept partials resume via HTTP Range.
    for (final token in _active.values) {
      token.cancel(_switchCancelReason);
    }
    _queue.clear();
    _progress.clear();
    _loadedAccountKey = account.key;

    final support = await getApplicationSupportDirectory();
    _dirPath = p.join(support.path, 'downloads', _segmentFor(account.key));
    await Directory(_dirPath!).create(recursive: true);

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKeyFor(account.key)) ?? [];
    _items = raw
        .map((s) {
          try {
            return DownloadItem.fromJson(jsonDecode(s));
          } catch (_) {
            return null;
          }
        })
        .whereType<DownloadItem>()
        .toList();

    // The app was killed mid-transfer: anything still marked queued/downloading
    // is flipped to failed. We keep any half-written file on disk so retrying
    // resumes it from where it left off (HTTP Range), rather than restarting.
    var changed = false;
    for (var i = 0; i < _items.length; i++) {
      final it = _items[i];
      if (it.status == DownloadStatus.queued ||
          it.status == DownloadStatus.downloading) {
        _items[i] = it.copyWith(status: DownloadStatus.failed);
        changed = true;
      }
    }
    if (changed) await _persist();
    notifyListeners();
    // Anything enqueued while this load was still resolving the directory
    // sat in _queue with _pump unable to start it — start it now.
    unawaited(_pump());
  }

  /// Queues [item] for download, unless it's already downloaded or in flight.
  Future<void> enqueue(DownloadItem item) async {
    final existing = _byId(item.id);
    if (existing != null &&
        (existing.status == DownloadStatus.completed ||
            existing.status == DownloadStatus.downloading ||
            existing.status == DownloadStatus.queued)) {
      return; // already here / in progress
    }
    if (existing != null) {
      _items.removeWhere((i) => i.id == item.id); // replace a failed one
    }
    _items.add(item.copyWith(status: DownloadStatus.queued));
    _queue.add(item.id);
    await _persist();
    notifyListeners();
    unawaited(_pump());
  }

  Future<void> retry(String id) async {
    final item = _byId(id);
    if (item == null || item.status != DownloadStatus.failed) return;
    _setStatus(id, DownloadStatus.queued);
    _queue.add(id);
    await _persist();
    notifyListeners();
    unawaited(_pump());
  }

  /// Aborts an in-flight/queued download and discards it (item + partial file).
  Future<void> cancel(String id) async {
    _queue.remove(id);
    final item = _byId(id);
    _items.removeWhere((i) => i.id == id);
    _progress.remove(id);
    await _persist();
    notifyListeners();
    final token = _active[id];
    if (token != null) {
      token.cancel('cancelled'); // _run cleans the partial file
    } else if (item != null) {
      await _deletePartial(item);
    }
  }

  /// Removes a completed (or failed) download: its metadata and its file.
  Future<void> deleteDownload(String id) async {
    if (_active.containsKey(id)) {
      await cancel(id);
      return;
    }
    final item = _byId(id);
    _items.removeWhere((i) => i.id == id);
    _progress.remove(id);
    await _persist();
    notifyListeners();
    if (item != null) await _deleteFile(item);
  }

  /// Deletes every download for the loaded account (files + metadata).
  Future<void> clearAll() async {
    for (final token in _active.values) {
      token.cancel('cleared');
    }
    _queue.clear();
    final toDelete = List<DownloadItem>.from(_items);
    _items = [];
    _progress.clear();
    await _persist();
    notifyListeners();
    for (final it in toDelete) {
      await _deleteFile(it);
    }
  }

  /// Total bytes the loaded account's completed files occupy on disk.
  Future<int> totalBytesOnDisk() async {
    if (_dirPath == null) return 0;
    var total = 0;
    for (final it in _items) {
      final f = File(p.join(_dirPath!, it.fileName));
      if (await f.exists()) total += await f.length();
    }
    return total;
  }

  /// Starts as many queued transfers as the concurrency limit allows. Cheap to
  /// call repeatedly — it no-ops once every slot is busy or the queue is empty.
  Future<void> _pump() async {
    if (_dirPath == null) return;
    while (_queue.isNotEmpty && _active.length < _maxConcurrent) {
      final id = _queue.removeAt(0);
      final item = _byId(id);
      if (item == null) continue; // cancelled before it started
      unawaited(_run(item));
    }
  }

  /// Runs a single transfer to completion (or failure/cancel), then refills the
  /// slot it frees. A cancel discards the partial; a plain failure keeps it so
  /// a retry can resume via HTTP Range.
  Future<void> _run(DownloadItem item) async {
    final id = item.id;
    final token = CancelToken();
    _active[id] = token;
    _setStatus(id, DownloadStatus.downloading);
    notifyListeners();
    final savePath = p.join(_dirPath!, item.fileName);
    try {
      await _downloader(
        item.remoteUrl,
        savePath,
        token: token,
        headers: item.headers,
        onProgress: (received, total) => _onProgress(id, received, total),
      );
      _progress.remove(id);
      _setStatus(id, DownloadStatus.completed);
      await _persist();
    } on DioException catch (e) {
      _progress.remove(id);
      if (e.type == DioExceptionType.cancel) {
        // Cancelled by the user (cancel()/clearAll(): the item is already
        // removed, so make sure the partial file goes too) — unless this is
        // an account switch, which keeps the partial for a later resume.
        if (e.error != _switchCancelReason) await _deleteFileAt(savePath);
      } else if (_byId(id) != null) {
        _setStatus(id, DownloadStatus.failed); // keep the partial for resume
        await _persist();
      }
    } catch (_) {
      _progress.remove(id);
      if (_byId(id) != null) {
        _setStatus(id, DownloadStatus.failed); // keep the partial for resume
        await _persist();
      }
    } finally {
      _active.remove(id);
      notifyListeners();
      unawaited(_pump()); // fill the slot this transfer just freed
    }
  }

  void _onProgress(String id, int received, int total) {
    _progress[id] = (received: received, total: total);
    final now = DateTime.now();
    if (now.difference(_lastProgressNotify).inMilliseconds >= 400) {
      _lastProgressNotify = now;
      notifyListeners();
    }
  }

  void _setStatus(String id, DownloadStatus status) {
    final idx = _items.indexWhere((i) => i.id == id);
    if (idx != -1) _items[idx] = _items[idx].copyWith(status: status);
  }

  Future<void> _deletePartial(DownloadItem item) =>
      _deleteFileAt(_dirPath == null ? null : p.join(_dirPath!, item.fileName));

  Future<void> _deleteFile(DownloadItem item) => _deletePartial(item);

  Future<void> _deleteFileAt(String? path) async {
    if (path == null) return;
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {
      // Best effort — a locked/again-missing file shouldn't crash anything.
    }
    await _writeValidator(path, null); // its resume sidecar goes with it
  }

  Future<void> _persist() async {
    final accountKey = _loadedAccountKey;
    if (accountKey == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _prefsKeyFor(accountKey),
      _items.map((i) => jsonEncode(i.toJson())).toList(),
    );
  }

  /// Wipes a removed account's downloads (files + metadata). Works whether or
  /// not [account] is the currently-loaded one.
  Future<void> deleteFor(Account account) async {
    if (_loadedAccountKey == account.key) {
      for (final token in _active.values) {
        token.cancel('account deleted');
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKeyFor(account.key));

    final support = await getApplicationSupportDirectory();
    final dir =
        Directory(p.join(support.path, 'downloads', _segmentFor(account.key)));
    if (await dir.exists()) {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
    if (_loadedAccountKey == account.key) {
      _items = [];
      _queue.clear();
      _progress.clear();
      _loadedAccountKey = null;
      _dirPath = null;
      notifyListeners();
    }
  }

  @visibleForTesting
  // ignore: avoid_setters_without_getters
  set downloaderForTesting(Downloader d) => _downloaderOverride = d;

  @visibleForTesting
  Future<void> resetForTesting() async {
    for (final token in _active.values) {
      token.cancel();
    }
    _active.clear();
    _items = [];
    _queue.clear();
    _progress.clear();
    _loadedAccountKey = null;
    _dirPath = null;
    _settingsLoaded = false;
    _maxConcurrent = 1;
    _bandwidthLimitKbps = 0;
    _rateLimiter.bytesPerSecond = 0;
  }
}

/// A token-bucket rate limiter shared by all in-flight transfers so the
/// configured speed cap applies to their *combined* throughput. [reserve]
/// debits a chunk's bytes and reports how long the caller must pause first to
/// stay under [bytesPerSecond]; 0 means unlimited (never pauses).
///
/// Pure and clock-injectable so its pacing can be unit-tested without real time.
class DownloadRateLimiter {
  DownloadRateLimiter(this.bytesPerSecond, {int Function()? nowMicros})
      : _nowMicros = nowMicros ?? (() => DateTime.now().microsecondsSinceEpoch),
        _allowance = bytesPerSecond.toDouble() {
    _lastMicros = _nowMicros();
  }

  /// Combined cap in bytes/second; 0 disables limiting. Mutable so the setting
  /// can change mid-transfer.
  int bytesPerSecond;

  final int Function() _nowMicros;
  double _allowance; // bytes currently permitted to send
  late int _lastMicros;

  /// Accounts for [bytes] about to be written and returns how long to wait
  /// first. Refills the bucket by the time elapsed since the last call, caps
  /// the burst at one second's worth, then debits the chunk; a negative balance
  /// becomes the wait (which the next call's elapsed-time refill cancels out).
  Duration reserve(int bytes) {
    if (bytesPerSecond <= 0) return Duration.zero;
    final now = _nowMicros();
    _allowance += (now - _lastMicros) / 1e6 * bytesPerSecond;
    _lastMicros = now;
    final ceiling = bytesPerSecond.toDouble();
    if (_allowance > ceiling) _allowance = ceiling;
    _allowance -= bytes;
    if (_allowance >= 0) return Duration.zero;
    return Duration(microseconds: (-_allowance / bytesPerSecond * 1e6).ceil());
  }
}
