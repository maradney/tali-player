import 'package:flutter/material.dart';

import '../../data/models/account.dart';
import '../../data/models/download_item.dart';
import '../../data/models/favorite_item.dart';
import '../../data/models/playback_progress.dart';
import '../../data/models/series_info.dart';
import '../../data/models/series_item.dart';
import '../../data/services/download_service.dart';
import '../../data/services/favorites_service.dart';
import '../../data/services/playback_service.dart';
import '../../data/services/watchlist_service.dart';
import '../../data/sources/media_source.dart';
import '../../l10n/app_localizations.dart';
import '../common/api_error_helper.dart';
import '../common/browse_states.dart';
import '../common/cached_poster_image.dart';
import '../common/expandable_text.dart';
import '../common/poster_backdrop.dart';
import '../downloads/download_button.dart';
import '../player/channel_player_screen.dart';

class SeriesDetailScreen extends StatefulWidget {
  final Account account;
  final SeriesItem series;

  const SeriesDetailScreen({
    super.key,
    required this.account,
    required this.series,
  });

  @override
  State<SeriesDetailScreen> createState() => _SeriesDetailScreenState();
}

class _SeriesDetailScreenState extends State<SeriesDetailScreen> {
  late final _source = MediaSource.forAccount(widget.account);

  bool _loading = true;
  String? _error;
  SeriesInfo? _info;

  FavoriteItem get _favoriteItem => FavoriteItem(
        type: 'series',
        id: widget.series.seriesId,
        name: widget.series.name,
        imageUrl: widget.series.coverUrl,
        categoryId: widget.series.categoryId,
      );

  /// App-bar star to add/remove this series from Favorites — mirrors the movie
  /// detail screen, so a series can be favorited from its detail too (not only
  /// from the grids).
  Widget _favoriteAction() => AnimatedBuilder(
        animation: FavoritesService.instance,
        builder: (context, _) {
          final isFav = FavoritesService.instance
              .isFavorite('series', widget.series.seriesId);
          return IconButton(
            icon: Icon(isFav ? Icons.star : Icons.star_border,
                color: isFav ? Colors.amber : null),
            onPressed: () => FavoritesService.instance.toggle(_favoriteItem),
          );
        },
      );

  /// App-bar toggle to add/remove this series from the watch-later queue,
  /// shared by every state of the screen's app bar.
  Widget _watchlistAction() => AnimatedBuilder(
        animation: WatchlistService.instance,
        builder: (context, _) {
          final l = AppLocalizations.of(context)!;
          final inList = WatchlistService.instance
              .isInWatchlist('series', widget.series.seriesId);
          return IconButton(
            icon: Icon(inList ? Icons.bookmark : Icons.bookmark_border),
            tooltip: inList ? l.removeFromWatchlist : l.addToWatchlist,
            onPressed: () => WatchlistService.instance.toggle(_favoriteItem),
          );
        },
      );

  // Computed once when the series loads, from the last-watched episode (if
  // any) - which season tab to open on, and which episode row to highlight
  // and scroll to within it.
  int _initialSeasonIndex = 0;
  String? _resumeEpisodeId;

  @override
  void initState() {
    super.initState();
    // Listen (rather than refreshing once after Navigator.push returns) so
    // this stays correct regardless of when the player screen actually
    // persists progress - its dispose() (where the final save happens)
    // fires after the pop's transition animation completes, which is later
    // than when the push's Future resolves.
    PlaybackService.instance.addListener(_onPlaybackChanged);
    _load();
  }

  @override
  void dispose() {
    PlaybackService.instance.removeListener(_onPlaybackChanged);
    super.dispose();
  }

  void _onPlaybackChanged() {
    // This can fire from PlaybackService.save() while a just-popped screen
    // is being unmounted (widget tree locked mid-frame) - defer to the next
    // frame so setState() is always safe to call here.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _info == null) return;
      final lastWatched = PlaybackService.instance
          .lastEpisodeForSeries(widget.series.seriesId);
      final id = lastWatched?.id;
      if (id == _resumeEpisodeId) return;
      setState(() {
        _resumeEpisodeId = id;
      });
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final info = await _source.getSeriesInfo(widget.series.seriesId);
      if (!mounted) return;
      final lastWatched =
          PlaybackService.instance.lastEpisodeForSeries(widget.series.seriesId);
      setState(() {
        _info = info;
        _loading = false;
        if (lastWatched != null) {
          final seasonIndex = info.seasons
              .indexWhere((s) => s.seasonNumber == lastWatched.seasonNumber);
          _initialSeasonIndex = seasonIndex >= 0 ? seasonIndex : 0;
          _resumeEpisodeId = lastWatched.id;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = describeApiError(e, widget.account, AppLocalizations.of(context)!);
        _loading = false;
      });
    }
  }

  /// The download descriptor for one episode (also its offline file's identity).
  DownloadItem _downloadItemFor(Season season, Episode episode) => DownloadItem(
        type: 'episode',
        id: episode.id,
        name: episode.title,
        seriesName: widget.series.name,
        seriesId: widget.series.seriesId,
        seasonNumber: season.seasonNumber,
        episodeNum: episode.episodeNum,
        categoryId: widget.series.categoryId,
        posterUrl: widget.series.coverUrl,
        containerExtension: episode.containerExtension,
        remoteUrl: _source.episodeUrl(episode),
        // Same headers streaming uses (M3U's default UA) — a UA-picky server
        // that plays fine must not 403 the download.
        headers: iptvVodHeaders(isM3u: widget.account.isM3u),
        status: DownloadStatus.queued,
        addedAt: DateTime.now().millisecondsSinceEpoch,
      );

  void _playEpisode(Season season, Episode episode) {
    // Play the local file when the episode is downloaded (offline playback).
    final svc = DownloadService.instance;
    final downloaded = svc.isDownloaded('episode', episode.id);
    final url = downloaded
        ? svc.localPathFor(_downloadItemFor(season, episode))!
        : _source.episodeUrl(episode);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChannelPlayerScreen(
          title: '${widget.series.name} - ${episode.title}',
          streamUrl: url,
          // M3U streams get the default browser UA (403-avoidance, like
          // live); pointless for a local file.
          httpHeaders: downloaded
              ? null
              : iptvVodHeaders(isM3u: widget.account.isM3u),
          // The series snapshot: star toggle in the player, and the cover
          // image on the watch-history entry it records (episodes log under
          // their series, so without this history tiles had no poster).
          favoriteItem: _favoriteItem,
          seriesName: widget.series.name,
          playbackRef: PlaybackRef(
            type: 'episode',
            id: episode.id,
            seriesId: widget.series.seriesId,
            seasonNumber: season.seasonNumber,
            episodeNum: episode.episodeNum,
            categoryId: widget.series.categoryId,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.series.name)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.series.name)),
        body: ErrorState(message: _error!, onRetry: _load),
      );
    }

    final seasons = _info!.seasons;
    if (seasons.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.series.name)),
        body: PosterBackdrop(
          posterUrl: _info?.coverUrl ?? widget.series.coverUrl,
          child: Column(
            children: [
              _SeriesHeader(series: widget.series, info: _info),
              Expanded(
                child: Center(
                    child: Text(AppLocalizations.of(context)!.noSeasonData)),
              ),
            ],
          ),
        ),
      );
    }

    return DefaultTabController(
      length: seasons.length,
      initialIndex: _initialSeasonIndex,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.series.name),
          actions: [_watchlistAction(), _favoriteAction()],
          bottom: TabBar(
            isScrollable: true,
            tabs: [for (final s in seasons) Tab(text: s.name)],
          ),
        ),
        body: PosterBackdrop(
          posterUrl: _info?.coverUrl ?? widget.series.coverUrl,
          // Fade out by the time the episode list starts, so list rows sit on
          // the plain background (the header is ~200px tall).
          height: 260,
          child: Column(
            children: [
              _SeriesHeader(series: widget.series, info: _info),
              Expanded(
                child: TabBarView(
                  children: [
                    for (final season in seasons)
                      _EpisodeList(
                        episodes: season.episodes,
                        highlightEpisodeId: _resumeEpisodeId,
                        onTap: (episode) => _playEpisode(season, episode),
                        downloadItemFor: (episode) =>
                            _downloadItemFor(season, episode),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Poster + name/plot/cast/director/genre overview shown above the
/// season tabs and episode list.
class _SeriesHeader extends StatelessWidget {
  final SeriesItem series;
  final SeriesInfo? info;

  const _SeriesHeader({required this.series, required this.info});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final coverUrl = info?.coverUrl ?? series.coverUrl;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 100,
              height: 150,
              child: coverUrl != null
                  ? CachedPosterImage(
                      imageUrl: coverUrl,
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
                Text(series.name, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 6),
                if (info?.ageRating != null || info?.rating != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
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
                if (info?.plot != null) ...[
                  const SizedBox(height: 6),
                  ExpandableText(text: info!.plot!, collapsedLines: 4),
                ],
              ],
            ),
          ),
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
      padding: const EdgeInsets.only(bottom: 2),
      child: RichText(
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
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
      child: Icon(Icons.tv, color: Theme.of(context).disabledColor),
    );
  }
}

/// [highlightEpisodeId], when set, marks that episode as "Continue
/// watching" and scrolls it into view once the list is laid out.
class _EpisodeList extends StatefulWidget {
  final List<Episode> episodes;
  final String? highlightEpisodeId;
  final void Function(Episode) onTap;
  final DownloadItem Function(Episode) downloadItemFor;

  const _EpisodeList({
    required this.episodes,
    required this.onTap,
    required this.downloadItemFor,
    this.highlightEpisodeId,
  });

  @override
  State<_EpisodeList> createState() => _EpisodeListState();
}

class _EpisodeListState extends State<_EpisodeList> {
  final _highlightKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (widget.highlightEpisodeId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _highlightKey.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(ctx,
              alignment: 0.3, duration: const Duration(milliseconds: 300));
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    if (widget.episodes.isEmpty) {
      return Center(child: Text(l.noEpisodesInSeason));
    }
    return ListView.separated(
      itemCount: widget.episodes.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final episode = widget.episodes[index];
        final isHighlighted = episode.id == widget.highlightEpisodeId;
        return ListTile(
          key: isHighlighted ? _highlightKey : null,
          tileColor: isHighlighted
              ? Theme.of(context).colorScheme.primaryContainer
              : null,
          leading: CircleAvatar(child: Text('${episode.episodeNum}')),
          title: Text(
            episode.title,
            style: isHighlighted ? const TextStyle(fontWeight: FontWeight.bold) : null,
          ),
          subtitle: isHighlighted ? Text(l.continueWatching) : null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DownloadButton(
                  item: widget.downloadItemFor(episode), compact: true),
              const Icon(Icons.play_arrow),
            ],
          ),
          onTap: () => widget.onTap(episode),
        );
      },
    );
  }
}

