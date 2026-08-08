import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'cached_poster_image.dart';
import 'continue_watching_bar.dart';

/// Generic poster grid - works for both Movies and Series since they're
/// both "grid of image + title, tap to go somewhere" at this level.
/// The caller supplies how to pull a title/image/tap-handler out of
/// whatever item type it's showing.
class PosterGrid<T> extends StatelessWidget {
  final List<T> items;
  final String Function(T item) titleOf;
  final String? Function(T item) posterUrlOf;
  final void Function(T item) onTap;
  final void Function(T item)? onLongPress;
  final bool Function(T item)? isFavorite;
  final void Function(T item)? onToggleFavorite;

  /// Watch-later toggle, rendered as a bookmark just below the favorite star.
  /// Both callbacks must be set for it to show (mirrors the favorite pair).
  final bool Function(T item)? isInWatchlist;
  final void Function(T item)? onToggleWatchlist;

  final double? Function(T item)? progressFraction;
  final String? Function(T item)? ratingOf;
  final bool Function(T item)? isLocked;

  /// When set, each tile shows a small × button (top-right) that calls this -
  /// a discoverable, mouse-friendly way to remove an item (e.g. from watch
  /// history), rather than relying only on long-press.
  final void Function(T item)? onRemove;

  /// Widest a tile is allowed to grow before another column is added - i.e.
  /// the grid density. Smaller = more, smaller posters. Defaults to the
  /// pre-density-setting value so callers that don't care keep the old look.
  final double idealTileWidth;

  const PosterGrid({
    super.key,
    required this.items,
    required this.titleOf,
    required this.posterUrlOf,
    required this.onTap,
    this.onLongPress,
    this.isFavorite,
    this.onToggleFavorite,
    this.isInWatchlist,
    this.onToggleWatchlist,
    this.progressFraction,
    this.ratingOf,
    this.isLocked,
    this.onRemove,
    this.idealTileWidth = 200.0,
  });

  // Between the ideal width and the point a new column gets added, tiles grow
  // to fill the extra window width instead of staying pinned at one fixed
  // size, which is what makes maximizing the window actually enlarge the
  // posters instead of just adding more of them.
  static const _gridPadding = 12.0;

  /// Grid columns for [available] width at a given [idealTileWidth].
  ///
  /// Rounds to the nearest column count rather than always up. Rounding up
  /// made the density setting do nothing on narrow windows: at a phone's ~387
  /// usable pixels, Comfortable (200) and Spacious (260) both ceil()'d to 2
  /// columns and rendered identically, and the same collision happens on a
  /// desktop window around 800px (4 and 4). Nearest keeps the three densities
  /// distinct wherever there are enough pixels to distinguish them, at the
  /// cost of tiles sometimes being slightly wider than ideal instead of
  /// always slightly narrower.
  static int posterColumnsFor(double available, double idealTileWidth) {
    if (available <= 0 || idealTileWidth <= 0) return 1;
    return (available / idealTileWidth).round().clamp(1, 100);
  }
  static const _spacing = 12.0;

  // Real poster proportions, applied via an explicit AspectRatio box
  // rather than baked into a whole-tile childAspectRatio guess - that way
  // BoxFit.cover only ever has to fill a correctly-shaped box, so it
  // never has to crop more than a real 2:3 poster naturally needs to.
  static const _posterAspectRatio = 2 / 3;
  static const _titleFontSize = 12.0;
  static const _titleGap = 4.0;

  /// Height reserved under the poster for up to 2 title lines. Derived from
  /// the real (scaled) font size rather than hard-coded — a fixed guess
  /// overflowed by a few pixels once the bundled font's line height came in
  /// taller than Roboto's. 1.5 is a safe ceiling for line-height ratios.
  static double _titleAreaHeight(BuildContext context) =>
      _titleGap +
      MediaQuery.textScalerOf(context).scale(_titleFontSize) * 1.5 * 2;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
          child: Text(AppLocalizations.of(context)!.noItemsInCategory));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth - _gridPadding * 2;
        final crossAxisCount = posterColumnsFor(available, idealTileWidth);
        final tileWidth =
            (available - _spacing * (crossAxisCount - 1)) / crossAxisCount;
        final tileHeight =
            tileWidth / _posterAspectRatio + _titleAreaHeight(context);

        return GridView.builder(
          padding: const EdgeInsets.all(_gridPadding),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisExtent: tileHeight,
            crossAxisSpacing: _spacing,
            mainAxisSpacing: _spacing,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            final posterUrl = posterUrlOf(item);
            final locked = isLocked?.call(item) ?? false;

            return InkWell(
              onTap: () => onTap(item),
              onLongPress: onLongPress == null ? null : () => onLongPress!(item),
              borderRadius: BorderRadius.circular(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AspectRatio(
                    aspectRatio: _posterAspectRatio,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          posterUrl != null
                              ? CachedPosterImage(
                                  imageUrl: posterUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      const _PosterFallback(),
                                )
                              : const _PosterFallback(),
                          if (isFavorite != null && onToggleFavorite != null)
                            Positioned(
                              top: 4,
                              right: 4,
                              child: GestureDetector(
                                onTap: () => onToggleFavorite!(item),
                                child: Icon(
                                  isFavorite!(item) ? Icons.star : Icons.star_border,
                                  color: Colors.amber,
                                  shadows: const [
                                    Shadow(color: Colors.black, blurRadius: 4),
                                  ],
                                ),
                              ),
                            ),
                          if (isInWatchlist != null && onToggleWatchlist != null)
                            Positioned(
                              // Directly under the favorite star (which sits at
                              // top: 4 and is a ~24px icon).
                              top: 32,
                              right: 4,
                              child: GestureDetector(
                                onTap: () => onToggleWatchlist!(item),
                                child: Icon(
                                  isInWatchlist!(item)
                                      ? Icons.bookmark
                                      : Icons.bookmark_border,
                                  color: Colors.pink,
                                  shadows: const [
                                    Shadow(color: Colors.black, blurRadius: 4),
                                  ],
                                ),
                              ),
                            ),
                          if (onRemove != null)
                            Positioned(
                              top: 4,
                              right: 4,
                              child: GestureDetector(
                                onTap: () => onRemove!(item),
                                child: Container(
                                  decoration: const BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle,
                                  ),
                                  padding: const EdgeInsets.all(3),
                                  child: const Icon(Icons.close,
                                      color: Colors.white, size: 16),
                                ),
                              ),
                            ),
                          if (ratingOf != null && ratingOf!(item) != null)
                            Positioned(
                              top: 4,
                              left: 4,
                              child: _RatingBadge(rating: ratingOf!(item)!),
                            ),
                          if (progressFraction != null &&
                              progressFraction!(item) != null)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: ContinueWatchingBar(
                                fraction: progressFraction!(item)!,
                              ),
                            ),
                          if (locked)
                            Positioned.fill(
                              child: Container(
                                color: Colors.black54,
                                child: const Center(
                                  child: Icon(Icons.lock,
                                      color: Colors.white, size: 32),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: _titleGap),
                  // Expanded (not fixed-size) so a font whose metrics exceed
                  // the reserved title area clips gracefully instead of
                  // throwing a RenderFlex overflow.
                  Expanded(
                    child: Text(
                      titleOf(item),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: _titleFontSize),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _RatingBadge extends StatelessWidget {
  final String rating;

  const _RatingBadge({required this.rating});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star, color: Colors.amber, size: 11),
          const SizedBox(width: 2),
          Text(
            rating,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _PosterFallback extends StatelessWidget {
  const _PosterFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(Icons.movie, color: Theme.of(context).disabledColor),
    );
  }
}