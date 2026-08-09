import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Self-healing for posters that got cached in an unusable state.
///
/// flutter_cache_manager treats any 200 or 202 response as a new file and
/// writes it without ever checking that the bytes are a decodable image
/// (`statusCodesNewFile` in web_helper.dart, and no content-type check). So an
/// HTML error page, a zero-byte body, or a body the CDN truncated but
/// terminated cleanly all get stored and indexed as if they were the poster.
/// Absent a `Cache-Control: max-age` from the server the entry is then valid
/// for seven days, and the cache is consulted before the network for every one
/// of them - so the image is not broken once, it is broken identically for a
/// week, and clearing the whole image cache by hand was the only way out.
///
/// The cure is to notice the decode failure and drop that one entry so the
/// next build refetches it.
///
/// Note this is specifically about *cached* corruption. A download that dies
/// mid-stream is a different and milder bug: web_helper adds the error to the
/// progress stream, which throws before `_store.putFile`, so the partial file
/// is orphaned on disk but never indexed and never served. That leaks space
/// rather than showing a broken poster, and Settings' "clear image cache"
/// remains the answer for it.
class PosterCacheRepair {
  PosterCacheRepair({
    Future<void> Function(String url)? removeFromDisk,
    Future<void> Function(String url)? evictFromMemory,
    this.maxRemembered = 512,
  })  : _removeFromDisk =
            removeFromDisk ?? ((url) => DefaultCacheManager().removeFile(url)),
        _evictFromMemory = evictFromMemory ??
            ((url) => CachedNetworkImageProvider(url).evict());

  static final PosterCacheRepair instance = PosterCacheRepair();

  final Future<void> Function(String url) _removeFromDisk;
  final Future<void> Function(String url) _evictFromMemory;

  /// How many URLs to remember having repaired. Bounded because a large
  /// catalog can put tens of thousands of poster URLs through here, and an
  /// unbounded set would be a slow leak for the whole session. Oldest entries
  /// are forgotten first, so a URL evicted from this set becomes eligible for
  /// one more repair - which is the right trade: the alternative is either
  /// unbounded memory or never healing again.
  final int maxRemembered;

  /// Insertion-ordered by Dart's default Set implementation, which is what
  /// makes "forget the oldest" work.
  final Set<String> _repaired = <String>{};

  /// Whether a failed load is worth evicting and retrying.
  ///
  /// Only decode and I/O failures are. An HTTP status error means the response
  /// never reached `_saveFile` and so nothing was ever cached - there is
  /// nothing to repair, and retrying would just re-request a URL the server
  /// already refused. That distinction matters here specifically: this app has
  /// tripped an Xtream panel's 429 rate limit before, and a grid of dead
  /// posters retrying on every scroll is exactly how to do it again.
  static bool isWorthRetrying(Object error) => error is! HttpExceptionWithStatus;

  /// Drops [url] from both caches, at most once per URL per session, and
  /// reports whether it did. False means it was already repaired (or isn't
  /// worth repairing) and the caller should leave the error on screen rather
  /// than retry.
  Future<bool> repairOnce(String url, Object error) async {
    if (!isWorthRetrying(error)) return false;
    if (!_repaired.add(url)) return false;
    if (_repaired.length > maxRemembered) {
      _repaired.remove(_repaired.first);
    }
    await _removeFromDisk(url);
    await _evictFromMemory(url);
    return true;
  }

  /// Lets a fresh session (or a manual "clear image cache") start over.
  void forgetAll() => _repaired.clear();

  int get rememberedCount => _repaired.length;
}
