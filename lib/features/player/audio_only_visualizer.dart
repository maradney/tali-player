import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Shown over the (black) video surface when a stream carries audio but no
/// video track — radio channels, mostly. A gently animated equalizer plus the
/// stream title, so the screen reads "this is playing" instead of "this is
/// broken". Purely decorative: the bars follow a fixed rhythm, not the audio.
class AudioOnlyVisualizer extends StatefulWidget {
  final String title;

  const AudioOnlyVisualizer({super.key, required this.title});

  @override
  State<AudioOnlyVisualizer> createState() => _AudioOnlyVisualizerState();
}

class _AudioOnlyVisualizerState extends State<AudioOnlyVisualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 96,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  for (var i = 0; i < _barCount; i++) ...[
                    _Bar(
                      // Each bar runs its own phase-shifted sine so the row
                      // ripples instead of pumping in unison.
                      fraction: 0.25 +
                          0.75 *
                              (0.5 +
                                  0.5 *
                                      math.sin(2 *
                                              math.pi *
                                              (_controller.value +
                                                  i * 0.13) +
                                          i)),
                      color: scheme.primary,
                    ),
                    if (i < _barCount - 1) const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Icon(Icons.radio, size: 28, color: scheme.onSurfaceVariant),
          const SizedBox(height: 8),
          Text(
            widget.title,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            AppLocalizations.of(context)!.audioOnlyStream,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  static const _barCount = 7;
}

class _Bar extends StatelessWidget {
  /// 0..1 share of the full bar height currently lit.
  final double fraction;
  final Color color;

  const _Bar({required this.fraction, required this.color});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: Container(
        width: 10,
        height: 96 * fraction.clamp(0.0, 1.0),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(5),
        ),
      ),
    );
  }
}
