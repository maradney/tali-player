import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'poster_cache_repair.dart';

/// Drop-in replacement for `Image.network` that caches to disk (and memory)
/// via cached_network_image - posters/logos already seen don't get
/// re-downloaded every time you navigate back to a grid/list, so scrolling
/// and re-opening screens feels instant after the first load.
///
/// Also self-heals a poster that was cached in an unusable state: see
/// [PosterCacheRepair] for why that happens and why the retry is capped at one
/// attempt per URL rather than left to fire on every rebuild.
class CachedPosterImage extends StatefulWidget {
  final String imageUrl;
  final BoxFit fit;
  final Widget Function(BuildContext context, Object error, StackTrace? stackTrace)
      errorBuilder;

  /// Injectable so tests can drive the retry without touching the real caches.
  final PosterCacheRepair? repair;

  const CachedPosterImage({
    super.key,
    required this.imageUrl,
    required this.errorBuilder,
    this.fit = BoxFit.cover,
    this.repair,
  });

  @override
  State<CachedPosterImage> createState() => _CachedPosterImageState();
}

class _CachedPosterImageState extends State<CachedPosterImage> {
  /// Bumped after a repair so the provider is rebuilt from scratch. Without a
  /// changing key, evicting the caches alone would not make CachedNetworkImage
  /// ask again - it holds the failed provider.
  int _attempt = 0;
  bool _repairing = false;

  PosterCacheRepair get _repair => widget.repair ?? PosterCacheRepair.instance;

  @override
  void didUpdateWidget(CachedPosterImage old) {
    super.didUpdateWidget(old);
    // A recycled tile pointing at a different poster starts over.
    if (old.imageUrl != widget.imageUrl) _attempt = 0;
  }

  Future<void> _onError(Object error) async {
    if (_repairing) return;
    _repairing = true;
    final retried = await _repair.repairOnce(widget.imageUrl, error);
    if (!mounted) {
      _repairing = false;
      return;
    }
    if (retried) setState(() => _attempt++);
    _repairing = false;
  }

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      key: ValueKey('${widget.imageUrl}#$_attempt'),
      imageUrl: widget.imageUrl,
      fit: widget.fit,
      fadeInDuration: Duration.zero, // avoid flicker while scrolling long lists
      errorWidget: (context, url, error) {
        // Fired during build, so the repair has to be deferred out of it.
        WidgetsBinding.instance.addPostFrameCallback((_) => _onError(error));
        return widget.errorBuilder(context, error, null);
      },
    );
  }
}
