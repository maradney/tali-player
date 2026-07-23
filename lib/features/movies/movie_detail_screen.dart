import 'package:flutter/material.dart';

import '../../data/models/account.dart';
import '../../data/models/download_item.dart';
import '../../data/models/favorite_item.dart';
import '../../data/models/movie.dart';
import '../../data/models/movie_info.dart';
import '../../data/models/playback_progress.dart';
import '../../data/services/download_service.dart';
import '../../data/services/favorites_service.dart';
import '../../data/services/watchlist_service.dart';
import '../../data/sources/media_source.dart';
import '../../l10n/app_localizations.dart';
import '../common/api_error_helper.dart';
import '../common/browse_states.dart';
import '../common/cached_poster_image.dart';
import '../common/poster_backdrop.dart';
import '../downloads/download_button.dart';
import '../player/channel_player_screen.dart';

class MovieDetailScreen extends StatefulWidget {
  final Account account;
  final Movie movie;

  const MovieDetailScreen({
    super.key,
    required this.account,
    required this.movie,
  });

  @override
  State<MovieDetailScreen> createState() => _MovieDetailScreenState();
}

class _MovieDetailScreenState extends State<MovieDetailScreen> {
  late final _source = MediaSource.forAccount(widget.account);

  bool _loading = true;
  String? _error;
  MovieInfo? _info;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final info = await _source.getVodInfo(widget.movie.streamId);
      if (!mounted) return;
      setState(() {
        _info = info;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = describeApiError(e, widget.account, AppLocalizations.of(context)!);
        _loading = false;
      });
    }
  }

  FavoriteItem get _favoriteItem => FavoriteItem(
        type: 'movie',
        id: widget.movie.streamId,
        name: widget.movie.name,
        imageUrl: widget.movie.posterUrl,
        categoryId: widget.movie.categoryId,
        extra: {'containerExtension': widget.movie.containerExtension},
      );

  DownloadItem get _downloadItem => DownloadItem(
        type: 'movie',
        id: widget.movie.streamId,
        name: widget.movie.name,
        categoryId: widget.movie.categoryId,
        posterUrl: widget.movie.posterUrl,
        containerExtension: widget.movie.containerExtension,
        remoteUrl: _source.vodUrl(widget.movie),
        // Same headers streaming uses (M3U's default UA) — a UA-picky server
        // that plays fine must not 403 the download.
        headers: iptvVodHeaders(isM3u: widget.account.isM3u),
        status: DownloadStatus.queued,
        addedAt: DateTime.now().millisecondsSinceEpoch,
      );

  void _play() {
    // Play the local file when it's downloaded, so a saved movie plays offline.
    final svc = DownloadService.instance;
    final downloaded = svc.isDownloaded('movie', widget.movie.streamId);
    final url = downloaded
        ? svc.localPathFor(_downloadItem)!
        : _source.vodUrl(widget.movie);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChannelPlayerScreen(
          title: widget.movie.name,
          streamUrl: url,
          // M3U streams get the default browser UA (403-avoidance, like
          // live); pointless for a local file.
          httpHeaders: downloaded
              ? null
              : iptvVodHeaders(isM3u: widget.account.isM3u),
          favoriteItem: _favoriteItem,
          playbackRef: PlaybackRef(
            type: 'movie',
            id: widget.movie.streamId,
            categoryId: widget.movie.categoryId,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.movie.name),
        actions: [
          AnimatedBuilder(
            animation: WatchlistService.instance,
            builder: (context, _) {
              final l = AppLocalizations.of(context)!;
              final inList = WatchlistService.instance
                  .isInWatchlist('movie', widget.movie.streamId);
              return IconButton(
                icon: Icon(inList ? Icons.bookmark : Icons.bookmark_border),
                tooltip: inList ? l.removeFromWatchlist : l.addToWatchlist,
                onPressed: () =>
                    WatchlistService.instance.toggle(_favoriteItem),
              );
            },
          ),
          AnimatedBuilder(
            animation: FavoritesService.instance,
            builder: (context, _) {
              final isFav = FavoritesService.instance
                  .isFavorite('movie', widget.movie.streamId);
              return IconButton(
                icon: Icon(isFav ? Icons.star : Icons.star_border,
                    color: isFav ? Colors.amber : null),
                onPressed: () =>
                    FavoritesService.instance.toggle(_favoriteItem),
              );
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : PosterBackdrop(
                  posterUrl: widget.movie.posterUrl,
                  child: _DetailBody(
                    movie: widget.movie,
                    info: _info,
                    onPlay: _play,
                    downloadItem: _downloadItem,
                  ),
                ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  final Movie movie;
  final MovieInfo? info;
  final VoidCallback onPlay;
  final DownloadItem downloadItem;

  const _DetailBody({
    required this.movie,
    required this.info,
    required this.onPlay,
    required this.downloadItem,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 140,
                  height: 210,
                  child: movie.posterUrl != null
                      ? CachedPosterImage(
                          imageUrl: movie.posterUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const _PosterFallback(),
                        )
                      : const _PosterFallback(),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(movie.name, style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 8),
                    if (info?.ageRating != null || info?.rating != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Wrap(
                          spacing: 8,
                          children: [
                            if (info?.ageRating != null)
                              Chip(
                                label: Text(info!.ageRating!),
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            if (info?.rating != null)
                              Chip(
                                avatar: const Icon(Icons.star, size: 16, color: Colors.amber),
                                label: Text(info!.rating!),
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                          ],
                        ),
                      ),
                    if (info?.genre != null) _InfoRow(label: l.genre, value: info!.genre!),
                    if (info?.director != null)
                      _InfoRow(label: l.director, value: info!.director!),
                    if (info?.cast != null) _InfoRow(label: l.cast, value: info!.cast!),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilledButton.icon(
                          onPressed: onPlay,
                          icon: const Icon(Icons.play_arrow),
                          label: Text(l.play),
                        ),
                        DownloadButton(item: downloadItem),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (info?.plot != null) ...[
            const SizedBox(height: 20),
            Text(l.overview, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(info!.plot!),
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        text: TextSpan(
          style: DefaultTextStyle.of(context).style,
          children: [
            TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.bold)),
            TextSpan(text: value),
          ],
        ),
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

