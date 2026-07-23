import 'package:flutter/material.dart';

/// Thin progress strip along the bottom edge of a poster/thumbnail,
/// marking an item as "in progress" - shown across the grids, favorites,
/// and search results so it's clear at a glance without opening the item.
///
/// [fraction] is how far into the tracked position (0-1). For series this
/// reflects progress within the last-watched episode, not the whole show -
/// there's no single meaningful fraction for a multi-episode series.
class ContinueWatchingBar extends StatelessWidget {
  final double fraction;
  final double height;

  const ContinueWatchingBar({super.key, required this.fraction, this.height = 4});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        children: [
          Container(color: Colors.black45),
          FractionallySizedBox(
            widthFactor: fraction.clamp(0.0, 1.0),
            child: Container(color: color),
          ),
        ],
      ),
    );
  }
}
