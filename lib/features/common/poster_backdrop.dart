import 'dart:ui';

import 'package:flutter/material.dart';

import 'cached_poster_image.dart';

/// Wraps a detail screen's body with its poster blown up, blurred, and faded
/// into the scaffold background across the top — the same treatment as the
/// Home hero banner's backdrop, adapted to themed screens: the scrim fades
/// toward the scaffold background (not a fixed dark), so the body's normal
/// text colors keep their contrast in both light and dark themes.
///
/// Purely decorative: with no [posterUrl] it's just [child], and the backdrop
/// layers are pointer-transparent so nothing under them loses taps.
class PosterBackdrop extends StatelessWidget {
  final String? posterUrl;
  final Widget child;

  /// How far down the backdrop reaches before it's fully the background color.
  final double height;

  const PosterBackdrop({
    super.key,
    required this.child,
    this.posterUrl,
    this.height = 340,
  });

  @override
  Widget build(BuildContext context) {
    final url = posterUrl;
    if (url == null) return child;
    final background = Theme.of(context).scaffoldBackgroundColor;
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: height,
          child: IgnorePointer(
            // ClipRect keeps the blur from bleeding past the backdrop band.
            child: ClipRect(
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: CachedPosterImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  // A missing poster just means no backdrop.
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: height,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    background.withValues(alpha: 0.6),
                    background,
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(child: child),
      ],
    );
  }
}
