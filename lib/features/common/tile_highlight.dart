import 'package:flutter/material.dart';

/// Gives a list row its own [Material] so its background and ink stay inside
/// the list.
///
/// `ListTile`'s `tileColor`/`selectedTileColor` are not painted by the tile.
/// As Flutter's own assertion puts it, "ListTile paints its background and ink
/// splashes on the nearest Material ancestor" - and on the series screen that
/// ancestor is the Scaffold body, which spans the header as well as the list.
/// The selected episode's colour could therefore be painted over the
/// description above it while scrolling.
///
/// The evidence that it was ink rather than a stray box is z-order: at full
/// resolution the description's text renders *on top of* the band. Only a
/// Material's ink layer paints beneath that Material's own children; anything
/// escaping the list would have covered the text instead.
///
/// Every row gets a Material - coloured when highlighted, transparent
/// otherwise - so ink always has a home inside the viewport that clips it.
/// Wrapping in a plain [ColoredBox] instead does not work and Flutter asserts
/// against it: the box would hide the very effects it is trying to contain.
///
/// Worth knowing before "simplifying" this back to `tileColor`: the leak does
/// not reproduce under `flutter test` at any scroll offset, with or without a
/// TabBarView, a Stack, or a transparent header - all of which were tried.
/// Widget tests also do not run Impeller, which the device does. It has only
/// ever been observed on a device, so that is where a regression would show.
class TileHighlight extends StatelessWidget {
  final bool highlighted;
  final Color color;
  final Widget child;

  const TileHighlight({
    super.key,
    required this.highlighted,
    required this.color,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => highlighted
      ? Material(color: color, child: child)
      : Material(type: MaterialType.transparency, child: child);
}
