import 'dart:ui';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../common/cached_poster_image.dart';

/// The Home dashboard's hero banner: "pick up where you left off" for the
/// most recent in-progress item. A wide card with the item's poster blurred
/// into the backdrop, a sharp poster thumbnail, the resume progress, and a
/// Resume button. Pure presentation — the dashboard picks the entry and
/// supplies the tap handler, so this stays trivially widget-testable.
class HomeHeroCard extends StatelessWidget {
  /// Small uppercase label above the title (e.g. "Continue watching").
  final String eyebrow;
  final String title;

  /// Optional second line, e.g. the series name for an episode.
  final String? subtitle;
  final String? posterUrl;

  /// Resume position as 0..1, drawn as a progress bar when present.
  final double? progress;
  final VoidCallback onResume;

  const HomeHeroCard({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.onResume,
    this.subtitle,
    this.posterUrl,
    this.progress,
  });

  /// Fixed dark backdrop fallback (and scrim base) so the white foreground
  /// text stays readable in both themes, with or without a poster.
  static const _backdropFallback = Color(0xFF20262E);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: 180,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Backdrop: the poster blown up + blurred, behind a dark scrim.
              Container(color: _backdropFallback),
              if (posterUrl != null)
                ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: CachedPosterImage(
                    imageUrl: posterUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: AlignmentDirectional.centerStart,
                    end: AlignmentDirectional.centerEnd,
                    colors: [Color(0xCC10141A), Color(0x8010141A)],
                  ),
                ),
              ),
              // Foreground: poster thumb + text + resume.
              Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: onResume,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        AspectRatio(
                          aspectRatio: 2 / 3,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: posterUrl != null
                                ? CachedPosterImage(
                                    imageUrl: posterUrl!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        const _HeroThumbFallback(),
                                  )
                                : const _HeroThumbFallback(),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                eyebrow.toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 11,
                                  letterSpacing: 1.5,
                                  color: Colors.white70,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              if (subtitle != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  subtitle!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 13, color: Colors.white70),
                                ),
                              ],
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  FilledButton.icon(
                                    onPressed: onResume,
                                    icon: const Icon(Icons.play_arrow),
                                    label: Text(l.resume),
                                  ),
                                  if (progress != null) ...[
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(2),
                                        child: LinearProgressIndicator(
                                          value: progress!.clamp(0.0, 1.0),
                                          minHeight: 4,
                                          backgroundColor: Colors.white24,
                                          color: scheme.primary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroThumbFallback extends StatelessWidget {
  const _HeroThumbFallback();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Colors.white12,
      child: Icon(Icons.movie, color: Colors.white38),
    );
  }
}
