import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'cached_poster_image.dart';
import 'continue_watching_bar.dart';

/// A horizontally-scrolling row of poster tiles with a section header and an
/// optional "View all" action — the building block for the Home dashboard's
/// Continue watching / Recently added sections. Complements [PosterGrid]
/// (which is the full-screen vertical grid); this is the compact carousel.
///
/// Desktop affordances: the mouse wheel scrolls the rail horizontally (instead
/// of doing nothing over it), paging chevrons appear on hover at whichever
/// ends can still scroll, and a gradient fade hints at off-screen content.
class PosterRail<T> extends StatefulWidget {
  final String title;
  final List<T> items;
  final VoidCallback? onViewAll;
  final String Function(T item) titleOf;
  final String? Function(T item) posterUrlOf;
  final void Function(T item) onTap;
  final String? Function(T item)? ratingOf;
  final double? Function(T item)? progressFraction;
  final bool Function(T item)? isLocked;

  /// Long-press handler — used to lock/unlock the item, matching the grids.
  final void Function(T item)? onLongPress;

  /// Watch-later toggle, drawn as a bookmark on the tile. Both must be set for
  /// it to show (mirrors [PosterGrid]).
  final bool Function(T item)? isInWatchlist;
  final void Function(T item)? onToggleWatchlist;

  /// Poster-tile width — driven by the grid-density setting so the rail
  /// matches the grids. Defaults to a compact rail width for callers that
  /// don't pass one.
  final double tileWidth;

  const PosterRail({
    super.key,
    required this.title,
    required this.items,
    required this.titleOf,
    required this.posterUrlOf,
    required this.onTap,
    this.onViewAll,
    this.ratingOf,
    this.progressFraction,
    this.isLocked,
    this.onLongPress,
    this.isInWatchlist,
    this.onToggleWatchlist,
    this.tileWidth = 118.0,
  });

  static const _posterAspectRatio = 2 / 3;

  @override
  State<PosterRail<T>> createState() => _PosterRailState<T>();
}

class _PosterRailState<T> extends State<PosterRail<T>> {
  final ScrollController _controller = ScrollController();
  bool _hovering = false;

  // Live scroll metrics (from notifications, so the initial layout counts
  // too) — drive which chevron/fade shows on each end.
  double _offset = 0;
  double _maxExtent = 0;

  bool get _canScrollBack => _offset > 1;
  bool get _canScrollForward => _offset < _maxExtent - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Maps the mouse wheel to horizontal rail scrolling. Registered through the
  /// pointer-signal resolver so the page behind only scrolls vertically when
  /// the rail can't take the event (i.e. it's already at that end).
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_controller.hasClients) return;
    final delta = event.scrollDelta.dy != 0
        ? event.scrollDelta.dy
        : event.scrollDelta.dx;
    if (delta == 0) return;
    if (delta > 0 && !_canScrollForward) return;
    if (delta < 0 && !_canScrollBack) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      _controller.jumpTo((_controller.offset + delta)
          .clamp(0.0, _controller.position.maxScrollExtent));
    });
  }

  /// Pages roughly one viewport per chevron click.
  void _page(double direction) {
    if (!_controller.hasClients) return;
    final viewport = _controller.position.viewportDimension;
    _controller.animateTo(
      (_controller.offset + direction * viewport * 0.8)
          .clamp(0.0, _controller.position.maxScrollExtent),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  bool _updateMetrics(ScrollMetrics metrics) {
    final offset = metrics.pixels;
    final max = metrics.maxScrollExtent;
    if (offset != _offset || max != _maxExtent) {
      setState(() {
        _offset = offset;
        _maxExtent = max;
      });
    }
    return false; // keep bubbling — nothing above cares, but be a good citizen
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final posterHeight = widget.tileWidth / PosterRail._posterAspectRatio;
    // Reserve two title lines, scaled by the user's text size, so the tile
    // never overflows its row (even at larger accessibility scales).
    final lineHeight = MediaQuery.textScalerOf(context).scale(12) * 1.4;
    final rowHeight = posterHeight + 4 + lineHeight * 2 + 4;
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 8, 8),
          child: Row(
            children: [
              Text(
                widget.title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const Spacer(),
              if (widget.onViewAll != null)
                TextButton(
                  onPressed: widget.onViewAll,
                  child: Text(l.viewAll),
                ),
            ],
          ),
        ),
        MouseRegion(
          onEnter: (_) => setState(() => _hovering = true),
          onExit: (_) => setState(() => _hovering = false),
          child: SizedBox(
            height: rowHeight,
            child: Stack(
              children: [
                Listener(
                  onPointerSignal: _onPointerSignal,
                  child: NotificationListener<ScrollMetricsNotification>(
                    onNotification: (n) => _updateMetrics(n.metrics),
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (n) => _updateMetrics(n.metrics),
                      child: ListView.separated(
                        controller: _controller,
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: widget.items.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (context, index) {
                          final item = widget.items[index];
                          return _RailTile(
                            width: widget.tileWidth,
                            aspectRatio: PosterRail._posterAspectRatio,
                            title: widget.titleOf(item),
                            posterUrl: widget.posterUrlOf(item),
                            rating: widget.ratingOf?.call(item),
                            progress: widget.progressFraction?.call(item),
                            locked: widget.isLocked?.call(item) ?? false,
                            onTap: () => widget.onTap(item),
                            onLongPress: widget.onLongPress == null
                                ? null
                                : () => widget.onLongPress!(item),
                            inWatchlist:
                                widget.isInWatchlist?.call(item) ?? false,
                            onToggleWatchlist: widget.onToggleWatchlist == null
                                ? null
                                : () => widget.onToggleWatchlist!(item),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                // Gradient fades hinting that the rail continues off-screen;
                // pointer-transparent so tiles under them stay clickable.
                _EdgeFade(
                  posterHeight: posterHeight,
                  atStart: true,
                  visible: _canScrollBack,
                ),
                _EdgeFade(
                  posterHeight: posterHeight,
                  atStart: false,
                  visible: _canScrollForward,
                ),
                // Hover chevrons page the rail. Icons point in the physical
                // direction the content will move toward (mirrored in RTL).
                _RailChevron(
                  posterHeight: posterHeight,
                  atStart: true,
                  visible: _hovering && _canScrollBack,
                  icon: isRtl ? Icons.chevron_right : Icons.chevron_left,
                  onPressed: () => _page(-1),
                ),
                _RailChevron(
                  posterHeight: posterHeight,
                  atStart: false,
                  visible: _hovering && _canScrollForward,
                  icon: isRtl ? Icons.chevron_left : Icons.chevron_right,
                  onPressed: () => _page(1),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A pointer-transparent gradient at one end of the rail, fading the tiles
/// toward the page background to signal there's more to scroll.
class _EdgeFade extends StatelessWidget {
  final double posterHeight;
  final bool atStart;
  final bool visible;

  const _EdgeFade({
    required this.posterHeight,
    required this.atStart,
    required this.visible,
  });

  @override
  Widget build(BuildContext context) {
    final background = Theme.of(context).scaffoldBackgroundColor;
    return PositionedDirectional(
      start: atStart ? 0 : null,
      end: atStart ? null : 0,
      top: 0,
      height: posterHeight,
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 150),
          child: Container(
            width: 28,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: atStart
                    ? AlignmentDirectional.centerStart
                    : AlignmentDirectional.centerEnd,
                end: atStart
                    ? AlignmentDirectional.centerEnd
                    : AlignmentDirectional.centerStart,
                colors: [background, background.withValues(alpha: 0)],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One hover paging button, vertically centered on the poster band.
class _RailChevron extends StatelessWidget {
  final double posterHeight;
  final bool atStart;
  final bool visible;
  final IconData icon;
  final VoidCallback onPressed;

  const _RailChevron({
    required this.posterHeight,
    required this.atStart,
    required this.visible,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return PositionedDirectional(
      start: atStart ? 4 : null,
      end: atStart ? null : 4,
      top: 0,
      height: posterHeight,
      child: Center(
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 150),
          child: IgnorePointer(
            ignoring: !visible, // invisible must not swallow tile taps
            child: IconButton.filledTonal(
              icon: Icon(icon),
              onPressed: onPressed,
            ),
          ),
        ),
      ),
    );
  }
}

class _RailTile extends StatelessWidget {
  final double width;
  final double aspectRatio;
  final String title;
  final String? posterUrl;
  final String? rating;
  final double? progress;
  final bool locked;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool inWatchlist;
  final VoidCallback? onToggleWatchlist;

  const _RailTile({
    required this.width,
    required this.aspectRatio,
    required this.title,
    required this.posterUrl,
    required this.rating,
    required this.progress,
    required this.locked,
    required this.onTap,
    required this.onLongPress,
    required this.inWatchlist,
    required this.onToggleWatchlist,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: aspectRatio,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    posterUrl != null
                        ? CachedPosterImage(
                            imageUrl: posterUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const _RailFallback(),
                          )
                        : const _RailFallback(),
                    if (rating != null)
                      Positioned(
                        top: 4,
                        left: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star,
                                  color: Colors.amber, size: 11),
                              const SizedBox(width: 2),
                              Text(
                                rating!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (onToggleWatchlist != null)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: GestureDetector(
                          onTap: onToggleWatchlist,
                          child: Icon(
                            inWatchlist ? Icons.bookmark : Icons.bookmark_border,
                            color: Colors.pink,
                            size: 20,
                            shadows: const [
                              Shadow(color: Colors.black, blurRadius: 4),
                            ],
                          ),
                        ),
                      ),
                    if (progress != null)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: ContinueWatchingBar(fraction: progress!),
                      ),
                    if (locked)
                      Positioned.fill(
                        child: Container(
                          color: Colors.black54,
                          child: const Center(
                            child: Icon(Icons.lock,
                                color: Colors.white, size: 28),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            // Flexible (not a fixed box) so the title fills exactly the space
            // left under the poster — the tile can never overflow its row.
            Expanded(
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RailFallback extends StatelessWidget {
  const _RailFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(Icons.movie, color: Theme.of(context).disabledColor),
    );
  }
}
