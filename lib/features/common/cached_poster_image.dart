import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Drop-in replacement for `Image.network` that caches to disk (and memory)
/// via cached_network_image - posters/logos already seen don't get
/// re-downloaded every time you navigate back to a grid/list, so scrolling
/// and re-opening screens feels instant after the first load.
class CachedPosterImage extends StatelessWidget {
  final String imageUrl;
  final BoxFit fit;
  final Widget Function(BuildContext context, Object error, StackTrace? stackTrace)
      errorBuilder;

  const CachedPosterImage({
    super.key,
    required this.imageUrl,
    required this.errorBuilder,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: fit,
      fadeInDuration: Duration.zero, // avoid flicker while scrolling long lists
      errorWidget: (context, url, error) => errorBuilder(context, error, null),
    );
  }
}
