import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/api/xtream_api_service.dart';
import '../../data/db/catalog_database.dart';
import '../../data/models/account.dart';
import '../../data/models/account_status.dart';
import '../../data/models/catalog_row.dart';
import '../../data/models/download_item.dart';
import '../../data/models/category.dart';
import '../../data/models/channel.dart';
import '../../data/models/favorite_item.dart';
import '../../data/models/home_strip.dart';
import '../../data/models/movie.dart';
import '../../data/models/search_result.dart';
import '../../data/models/series_item.dart';
import '../../data/models/watch_history_entry.dart';
import '../../data/services/catalog_sync_service.dart';
import '../../data/services/download_service.dart';
import '../../data/services/favorites_service.dart';
import '../../data/services/home_strips_service.dart';
import '../../data/services/kids_filter_service.dart';
import '../../data/services/pin_lock_service.dart';
import '../../data/services/playback_service.dart';
import '../../data/services/settings_service.dart';
import '../../data/services/watch_history_service.dart';
import '../../data/services/watchlist_service.dart';
import '../../data/sources/media_source.dart';
import '../../l10n/app_localizations.dart';
import '../common/category_label.dart';
import '../common/downloads_button.dart';
import '../common/layout_breakpoints.dart';
import '../common/pin_dialogs.dart';
import '../common/poster_rail.dart';
import '../downloads/downloads_screen.dart';
import '../movies/movie_detail_screen.dart';
import '../player/channel_player_screen.dart';
import '../series/series_detail_screen.dart';
import 'home_hero_card.dart';
import 'home_search_pill.dart';
import 'home_strips_editor.dart';

/// The default landing page: a glanceable dashboard built entirely from local
/// / cached data (no blocking API calls on open), so it renders instantly and
/// offline. Greeting + quick links + Continue watching + Recently added rails.
/// Live TV's own network fetch is deferred until the user actually opens it.
class HomeDashboardScreen extends StatefulWidget {
  final Account account;
  final VoidCallback onOpenLiveTv;
  final VoidCallback onOpenMovies;
  final VoidCallback onOpenSeries;
  final VoidCallback onOpenRecentlyAdded;
  final VoidCallback onOpenWatchlist;
  final VoidCallback onOpenFavorites;

  /// Opens the Search destination. Reached from the pill below the header on a
  /// phone, where Search is otherwise the last entry of the "More" sheet.
  final VoidCallback onOpenSearch;

  /// Which content types have items — drives which quick cards to show, so a
  /// hidden (empty) type's card doesn't open an empty screen. Mirrors the
  /// shell's nav-destination hiding.
  final Set<ContentType> availableTypes;

  const HomeDashboardScreen({
    super.key,
    required this.account,
    required this.onOpenLiveTv,
    required this.onOpenMovies,
    required this.onOpenSeries,
    required this.onOpenRecentlyAdded,
    required this.onOpenWatchlist,
    required this.onOpenFavorites,
    required this.onOpenSearch,
    required this.availableTypes,
  });

  @override
  State<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends State<HomeDashboardScreen> {
  final _api = XtreamApiService();
  late final String _accountKey = CatalogRow.accountKeyFor(widget.account);
  late final _source = MediaSource.forAccount(widget.account);

  List<SearchResult> _recentlyAdded = [];

  /// Items per enabled category strip, keyed by [HomeStrip.key].
  Map<String, List<SearchResult>> _categoryItems = {};
  int? _channelCount;
  AccountStatus? _status;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    CatalogSyncService.instance.addListener(_onSyncChanged);
    // A strip config change can add a category rail whose data isn't loaded
    // yet — refresh the local queries whenever the layout changes.
    HomeStripsService.instance.addListener(_onSyncChanged);
    _loadLocal();
    _loadStatus(); // network, but non-blocking - the page renders without it
    // Keep the greeting clock current without a heavy rebuild loop.
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    CatalogSyncService.instance.removeListener(_onSyncChanged);
    HomeStripsService.instance.removeListener(_onSyncChanged);
    _clock?.cancel();
    super.dispose();
  }

  void _onSyncChanged() {
    if (mounted) _loadLocal();
  }

  Future<void> _loadLocal() async {
    final recent =
        await CatalogDatabase.instance.recentlyAdded(_accountKey, limit: 20);
    final channels = await CatalogDatabase.instance
        .countFor(_accountKey, type: ContentType.live);
    // One capped query per enabled category strip — still all-local.
    final categoryItems = <String, List<SearchResult>>{};
    for (final strip in HomeStripsService.instance.enabledStrips) {
      if (strip.type != HomeStripType.category) continue;
      final rows = await CatalogDatabase.instance.itemsInCategory(
          _accountKey, strip.categoryType!, strip.categoryId!,
          limit: 20);
      categoryItems[strip.key] =
          rows.map((r) => r.toSearchResult()).toList();
    }
    if (!mounted) return;
    setState(() {
      _recentlyAdded = recent.map((r) => r.toSearchResult()).toList();
      _categoryItems = categoryItems;
      _channelCount = channels;
    });
  }

  Future<void> _loadStatus() async {
    if (widget.account.isM3u) return; // M3U has no account status
    try {
      final status = await _api.getAccountStatus(widget.account);
      if (mounted) setState(() => _status = status);
    } catch (_) {
      // Silent - the expiry line just doesn't show if the panel is unreachable.
    }
  }

  /// The hero banner's entry: the most recently watched in-progress item that
  /// isn't PIN-locked (a lock would leak the poster full-width; the rail shows
  /// locked tiles obscured instead). Null hides the hero.
  WatchHistoryEntry? _heroEntry() {
    for (final e in _continueWatching()) {
      if (!_entryLocked(e)) return e;
    }
    return null;
  }

  /// In-progress movies/episodes, newest-watched first, one tile per
  /// movie/series. Driven from watch history (which carries the poster/title
  /// snapshot) filtered to items that still have a resume position.
  List<WatchHistoryEntry> _continueWatching() {
    final seen = <String>{};
    final out = <WatchHistoryEntry>[];
    for (final e in WatchHistoryService.instance.entries) {
      if (e.type != 'movie' && e.type != 'episode') continue;
      if (!PlaybackService.instance.isInProgress(e.type, e.id)) continue;
      // Kids allowlist: episodes map to their series (how it's keyed); no-op
      // when disabled. Also gates the hero, which reads this list.
      final kidsType = e.type == 'episode' ? 'series' : e.type;
      final kidsId = e.type == 'episode' ? (e.seriesId ?? e.id) : e.id;
      if (KidsFilterService.instance
          .isHiddenForItem(kidsType, kidsId, categoryId: e.categoryId)) {
        continue;
      }
      final dedupeKey =
          e.type == 'episode' ? 'series:${e.seriesId ?? e.id}' : 'movie:${e.id}';
      if (!seen.add(dedupeKey)) continue;
      out.add(e);
    }
    return out;
  }

  bool _entryLocked(WatchHistoryEntry e) => PinLockService.instance
      .isLocked(e.type == 'episode' ? 'series' : e.type, e.id,
          categoryId: e.categoryId);

  bool _resultLocked(SearchResult r) => PinLockService.instance
      .isLocked(r.type.name, r.id, categoryId: r.categoryId);

  /// Recently-added minus anything in a locked *category* (hidden wholesale,
  /// not just gated on open). Individually-locked items stay, shown obscured.
  /// Read inside the PinLockService-listening builder, so it reacts to locks.
  List<SearchResult> get _visibleRecentlyAdded => _recentlyAdded
      .where((r) => !PinLockService.instance.isCategoryLockedForItem(
              r.type.name, r.id, categoryId: r.categoryId) &&
          !KidsFilterService.instance
              .isHiddenForItem(r.type.name, r.id, categoryId: r.categoryId))
      .toList();

  Future<void> _openEntry(WatchHistoryEntry entry) async {
    if (_entryLocked(entry)) {
      final ok = await requirePin(context,
          title: AppLocalizations.of(context)!.enterPinToOpen(entry.name));
      if (!ok) return;
    }
    if (!mounted) return;
    switch (entry.type) {
      case 'movie':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MovieDetailScreen(
              account: widget.account,
              movie: Movie(
                streamId: entry.id,
                name: entry.name,
                categoryId: entry.categoryId ?? '',
                containerExtension:
                    entry.extra['containerExtension'] as String? ?? 'mp4',
                posterUrl: entry.imageUrl,
              ),
            ),
          ),
        );
        break;
      case 'episode':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SeriesDetailScreen(
              account: widget.account,
              series: SeriesItem(
                seriesId: entry.seriesId ?? entry.id,
                name: entry.name,
                categoryId: entry.categoryId ?? '',
                coverUrl: entry.imageUrl,
              ),
            ),
          ),
        );
        break;
    }
  }

  Future<void> _openResult(SearchResult r) async {
    if (_resultLocked(r)) {
      final ok = await requirePin(context,
          title: AppLocalizations.of(context)!.enterPinToOpen(r.name));
      if (!ok) return;
    }
    if (!mounted) return;
    if (r.type == ContentType.movie) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              MovieDetailScreen(account: widget.account, movie: r.raw),
        ),
      );
    } else if (r.type == ContentType.series) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              SeriesDetailScreen(account: widget.account, series: r.raw),
        ),
      );
    } else if (r.type == ContentType.live) {
      // Live category rails: play directly, like tapping a search result.
      final Channel channel = r.raw;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChannelPlayerScreen(
            title: r.name,
            streamUrl: _source.liveUrl(channel),
            httpHeaders:
                iptvStreamHeaders(channel, isM3u: widget.account.isM3u),
            epgFuture: _source.getShortEpg(channel.streamId),
            favoriteItem: FavoriteItem(
              type: 'live',
              id: channel.streamId,
              name: channel.name,
              imageUrl: channel.logoUrl,
              categoryId: channel.categoryId,
            ),
          ),
        ),
      );
    }
  }

  bool _watchlistLocked(FavoriteItem i) => PinLockService.instance
      .isLocked(i.type, i.id, categoryId: i.categoryId);

  // --- Watch-later targets ---------------------------------------------------
  // Watchlist holds movies/series only, so a continue-watching *episode* maps
  // to its parent series; movies map to themselves.

  String _entryWatchlistType(WatchHistoryEntry e) =>
      e.type == 'episode' ? 'series' : 'movie';
  String _entryWatchlistId(WatchHistoryEntry e) =>
      e.type == 'episode' ? (e.seriesId ?? e.id) : e.id;

  FavoriteItem _watchLaterForEntry(WatchHistoryEntry e) => FavoriteItem(
        type: _entryWatchlistType(e),
        id: _entryWatchlistId(e),
        name: e.name,
        imageUrl: e.imageUrl,
        categoryId: e.categoryId,
        extra: {
          if (e.type == 'movie')
            'containerExtension':
                e.extra['containerExtension'] as String? ?? 'mp4',
        },
      );

  FavoriteItem _watchLaterForResult(SearchResult r) => FavoriteItem(
        type: r.type.name,
        id: r.id,
        name: r.name,
        imageUrl: r.imageUrl,
        categoryId: r.categoryId,
        extra: {
          if (r.type == ContentType.movie && r.raw is Movie)
            'containerExtension': (r.raw as Movie).containerExtension,
          if (r.rating != null) 'rating': r.rating,
        },
      );

  /// Newest-added first (the stored list appends on add), capped for the rail.
  List<FavoriteItem> _watchlist() => WatchlistService.instance.items.reversed
      .where((i) => !KidsFilterService.instance
          .isHiddenForItem(i.type, i.id, categoryId: i.categoryId))
      .take(20)
      .toList();

  Future<void> _openWatchlistItem(FavoriteItem item) async {
    if (_watchlistLocked(item)) {
      final ok = await requirePin(context,
          title: AppLocalizations.of(context)!.enterPinToOpen(item.name));
      if (!ok) return;
    }
    if (!mounted) return;
    if (item.type == 'movie') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MovieDetailScreen(
            account: widget.account,
            movie: Movie(
              streamId: item.id,
              name: item.name,
              categoryId: item.categoryId ?? '',
              containerExtension:
                  item.extra['containerExtension'] as String? ?? 'mp4',
              posterUrl: item.imageUrl,
            ),
          ),
        ),
      );
    } else if (item.type == 'series') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SeriesDetailScreen(
            account: widget.account,
            series: SeriesItem(
              seriesId: item.id,
              name: item.name,
              categoryId: item.categoryId ?? '',
              coverUrl: item.imageUrl,
            ),
          ),
        ),
      );
    }
  }

  /// Newest-favorited first, capped for the rail.
  List<FavoriteItem> _favorites() => FavoritesService.instance.items.reversed
      .where((i) => !KidsFilterService.instance
          .isHiddenForItem(i.type, i.id, categoryId: i.categoryId))
      .take(20)
      .toList();

  /// Favorites can be live channels (unlike the watchlist) — those play
  /// directly; movies/series share the watchlist open path.
  Future<void> _openFavorite(FavoriteItem item) async {
    if (item.type != 'live') return _openWatchlistItem(item);
    if (_watchlistLocked(item)) {
      final ok = await requirePin(context,
          title: AppLocalizations.of(context)!.enterPinToOpen(item.name));
      if (!ok) return;
    }
    if (!mounted) return;
    // The favorite is a bare snapshot; resolveChannel re-reads the M3U
    // catalog so the channel gets its playable URL (and any headers) back.
    // Identity for Xtream.
    final channel = await _source.resolveChannel(Channel(
      streamId: item.id,
      name: item.name,
      categoryId: item.categoryId ?? '',
      logoUrl: item.imageUrl,
    ));
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChannelPlayerScreen(
          title: channel.name,
          streamUrl: _source.liveUrl(channel),
          httpHeaders: iptvStreamHeaders(channel, isM3u: widget.account.isM3u),
          epgFuture: _source.getShortEpg(channel.streamId),
          favoriteItem: item,
        ),
      ),
    );
  }

  /// Completed downloads, newest first — the offline-ready rail. Episodes map
  /// to their series for the kids allowlist (no-op when disabled).
  List<DownloadItem> _downloads() => DownloadService.instance.items
      .where((d) =>
          d.status == DownloadStatus.completed &&
          !KidsFilterService.instance.isHiddenForItem(
              d.type == 'episode' ? 'series' : d.type,
              d.type == 'episode' ? (d.seriesId ?? d.id) : d.id,
              categoryId: d.categoryId))
      .take(20)
      .toList();

  bool _downloadLocked(DownloadItem item) {
    final lockType = item.type == 'episode' ? 'series' : 'movie';
    final lockId =
        item.type == 'episode' ? (item.seriesId ?? item.id) : item.id;
    return PinLockService.instance
        .isLocked(lockType, lockId, categoryId: item.categoryId);
  }

  void _openDownloads() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DownloadsScreen(account: widget.account),
      ),
    );
  }

  Future<void> _playDownload(DownloadItem item) async {
    final path = DownloadService.instance.localPathFor(item);
    if (path == null) return;
    if (_downloadLocked(item)) {
      final ok = await requirePin(context,
          title: AppLocalizations.of(context)!.enterPinToOpen(item.name));
      if (!ok) return;
    }
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChannelPlayerScreen(
          title: item.seriesName != null
              ? '${item.seriesName} - ${item.name}'
              : item.name,
          streamUrl: path,
          seriesName: item.seriesName,
          // Poster for the history entry this playback records (and the
          // favorite star), same as playing from the detail screens.
          favoriteItem: item.toFavoriteItem(),
          playbackRef: item.playbackRef,
        ),
      ),
    );
  }

  String _greeting(AppLocalizations l) {
    final hour = DateTime.now().hour;
    if (hour < 12) return l.greetingMorning;
    if (hour < 18) return l.greetingAfternoon;
    return l.greetingEvening;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final time = MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay.now());

    return Scaffold(
      body: SafeArea(
        child: AnimatedBuilder(
          animation: Listenable.merge([
            WatchHistoryService.instance,
            WatchlistService.instance,
            FavoritesService.instance,
            DownloadService.instance,
            PlaybackService.instance,
            PinLockService.instance,
            HomeStripsService.instance, // the layout itself is editable
            SettingsService.instance, // grid density drives the rail tile size
          ]),
          builder: (context, _) {
            final tileWidth = SettingsService.instance.gridIdealTileWidth;
            // The configured strips, in order; a strip with nothing to show
            // renders nothing (an empty rail is clutter, not information).
            final rails = <Widget>[];
            for (final strip in HomeStripsService.instance.enabledStrips) {
              final rail = _railFor(strip, l, tileWidth);
              if (rail != null) rails.add(rail);
            }
            final hero = _heroEntry();
            // Cap the content width on very wide windows — a full-bleed rail
            // on an ultrawide reads as one endless strip, and the header
            // drifts away from the cards.
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1280),
                child: ListView(
                  children: [
                    _Header(
                      greeting: _greeting(l),
                      time: time,
                      status: _status,
                      account: widget.account,
                      onCustomize: _openCustomize,
                    ),
                    // Below the greeting rather than above it: the header says
                    // whose dashboard this is, and a search field above that
                    // reads as chrome for the whole app instead of a thing on
                    // this screen. Phone-only - the desktop rail already lists
                    // Search permanently. Keyed off the window width, not this
                    // widget's constraints, which exclude that rail.
                    if (showsHomeSearchPill(MediaQuery.sizeOf(context).width))
                      HomeSearchPill(
                        hint: l.searchHint,
                        onTap: widget.onOpenSearch,
                      ),
                    if (hero != null)
                      HomeHeroCard(
                        eyebrow: l.continueWatching,
                        title: hero.name,
                        // Episodes log the series as [name]; point at the
                        // exact episode when the numbers are known.
                        subtitle: (hero.seasonNumber != null &&
                                hero.episodeNum != null)
                            ? 'S${hero.seasonNumber} · E${hero.episodeNum}'
                            : null,
                        posterUrl: hero.imageUrl,
                        progress: PlaybackService.instance
                            .progressFraction(hero.type, hero.id),
                        onResume: () => _openEntry(hero),
                      ),
                    _QuickCards(
                      channelCount: _channelCount,
                      availableTypes: widget.availableTypes,
                      onOpenLiveTv: widget.onOpenLiveTv,
                      onOpenMovies: widget.onOpenMovies,
                      onOpenSeries: widget.onOpenSeries,
                    ),
                    const SizedBox(height: 8),
                    // Nothing watched/saved yet: say so, instead of leaving a
                    // silent blank page under the cards on a fresh playlist.
                    if (rails.isEmpty && hero == null)
                      const _EmptyDashboardHint()
                    else
                      ...rails,
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _openCustomize() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => HomeStripsEditor(
        account: widget.account,
        availableTypes: widget.availableTypes,
      ),
    );
  }

  /// The rail widget for one enabled strip, or null when it has nothing to
  /// show right now.
  Widget? _railFor(HomeStrip strip, AppLocalizations l, double tileWidth) {
    switch (strip.type) {
      case HomeStripType.continueWatching:
        final continueWatching = _continueWatching();
        if (continueWatching.isEmpty) return null;
        return PosterRail<WatchHistoryEntry>(
                    title: l.continueWatching,
                    items: continueWatching,
                    tileWidth: tileWidth,
                    titleOf: (e) => e.name,
                    posterUrlOf: (e) => e.imageUrl,
                    onTap: _openEntry,
                    isLocked: _entryLocked,
                    onLongPress: (e) => toggleItemLockPrompt(
                      context,
                      type: e.type == 'episode' ? 'series' : e.type,
                      id: e.id,
                      name: e.name,
                    ),
                    isInWatchlist: (e) => WatchlistService.instance
                        .isInWatchlist(
                            _entryWatchlistType(e), _entryWatchlistId(e)),
                    onToggleWatchlist: (e) => WatchlistService.instance
                        .toggle(_watchLaterForEntry(e)),
                    progressFraction: (e) => PlaybackService.instance
                        .progressFraction(e.type, e.id),
                  );

      case HomeStripType.watchlist:
        final watchlist = _watchlist();
        if (watchlist.isEmpty) return null;
        return PosterRail<FavoriteItem>(
                    title: l.watchlistTitle,
                    items: watchlist,
                    tileWidth: tileWidth,
                    onViewAll: widget.onOpenWatchlist,
                    titleOf: (i) => i.name,
                    posterUrlOf: (i) => i.imageUrl,
                    ratingOf: (i) => i.extra['rating'] as String?,
                    onTap: _openWatchlistItem,
                    isLocked: _watchlistLocked,
                    onLongPress: (i) => toggleItemLockPrompt(
                      context,
                      type: i.type,
                      id: i.id,
                      name: i.name,
                    ),
                    // These are all in the watchlist by definition, so the
                    // bookmark shows filled and tapping it removes the item.
                    isInWatchlist: (i) =>
                        WatchlistService.instance.isInWatchlist(i.type, i.id),
                    onToggleWatchlist: (i) =>
                        WatchlistService.instance.toggle(i),
                    progressFraction: (i) => PlaybackService.instance
                        .progressFraction(i.type, i.id),
                  );

      case HomeStripType.recentlyAdded:
        final recentlyAdded = _visibleRecentlyAdded;
        if (recentlyAdded.isEmpty) return null;
        return PosterRail<SearchResult>(
                    title: l.recentlyAddedTitle,
                    items: recentlyAdded,
                    tileWidth: tileWidth,
                    onViewAll: widget.onOpenRecentlyAdded,
                    titleOf: (r) => r.name,
                    posterUrlOf: (r) => r.imageUrl,
                    ratingOf: (r) => r.rating,
                    onTap: _openResult,
                    isLocked: _resultLocked,
                    onLongPress: (r) => toggleItemLockPrompt(
                      context,
                      type: r.type.name,
                      id: r.id,
                      name: r.name,
                    ),
                    isInWatchlist: (r) => WatchlistService.instance
                        .isInWatchlist(r.type.name, r.id),
                    onToggleWatchlist: (r) => WatchlistService.instance
                        .toggle(_watchLaterForResult(r)),
                    progressFraction: (r) => PlaybackService.instance
                        .progressFraction(r.type.name, r.id),
                  );

      case HomeStripType.downloads:
        final downloads = _downloads();
        if (downloads.isEmpty) return null;
        return PosterRail<DownloadItem>(
                    title: l.downloadsTitle,
                    items: downloads,
                    tileWidth: tileWidth,
                    onViewAll: _openDownloads,
                    titleOf: (d) => d.seriesName ?? d.name,
                    posterUrlOf: (d) => d.posterUrl,
                    onTap: _playDownload,
                    isLocked: _downloadLocked,
                  );

      case HomeStripType.favorites:
        final favorites = _favorites();
        if (favorites.isEmpty) return null;
        return PosterRail<FavoriteItem>(
          title: l.favoritesTitle,
          items: favorites,
          tileWidth: tileWidth,
          onViewAll: widget.onOpenFavorites,
          titleOf: (i) => i.name,
          posterUrlOf: (i) => i.imageUrl,
          ratingOf: (i) => i.extra['rating'] as String?,
          onTap: _openFavorite,
          isLocked: _watchlistLocked,
          onLongPress: (i) => toggleItemLockPrompt(
            context,
            type: i.type,
            id: i.id,
            name: i.name,
          ),
          progressFraction: (i) =>
              PlaybackService.instance.progressFraction(i.type, i.id),
        );

      case HomeStripType.category:
        // Locked-category filtering matches Recently added: a locked category
        // hides its items (and with them the whole rail) outright.
        final items = (_categoryItems[strip.key] ?? const <SearchResult>[])
            .where((r) => !PinLockService.instance.isCategoryLockedForItem(
                    r.type.name, r.id, categoryId: r.categoryId) &&
                !KidsFilterService.instance
                    .isHiddenForItem(r.type.name, r.id, categoryId: r.categoryId))
            .toList();
        if (items.isEmpty) return null;
        final isLive = strip.categoryType == ContentType.live;
        return PosterRail<SearchResult>(
          title: categoryDisplayName(
            Category(
              categoryId: strip.categoryId!,
              categoryName: strip.categoryName ?? strip.categoryId!,
            ),
            l,
          ),
          items: items,
          tileWidth: tileWidth,
          titleOf: (r) => r.name,
          posterUrlOf: (r) => r.imageUrl,
          ratingOf: (r) => r.rating,
          onTap: _openResult,
          isLocked: _resultLocked,
          onLongPress: (r) => toggleItemLockPrompt(
            context,
            type: r.type.name,
            id: r.id,
            name: r.name,
          ),
          // Watch-later is a movie/series concept; live rails get no bookmark.
          isInWatchlist: isLive
              ? null
              : (r) => WatchlistService.instance
                  .isInWatchlist(r.type.name, r.id),
          onToggleWatchlist: isLive
              ? null
              : (r) => WatchlistService.instance
                  .toggle(_watchLaterForResult(r)),
          progressFraction: (r) =>
              PlaybackService.instance.progressFraction(r.type.name, r.id),
        );
    }
  }
}

/// Shown instead of the rails on a brand-new playlist (nothing watched,
/// saved, or downloaded yet) so the dashboard doesn't look broken-empty.
class _EmptyDashboardHint extends StatelessWidget {
  const _EmptyDashboardHint();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Column(
        children: [
          Icon(Icons.movie_filter_outlined, size: 48, color: scheme.outline),
          const SizedBox(height: 12),
          Text(
            l.homeEmptyTitle,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            l.homeEmptyBody,
            style: TextStyle(color: scheme.outline),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String greeting;
  final String time;
  final AccountStatus? status;
  final Account account;
  final VoidCallback onCustomize;

  const _Header({
    required this.greeting,
    required this.time,
    required this.status,
    required this.account,
    required this.onCustomize,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final subtle = Theme.of(context).colorScheme.outline;
    // The greeting/title on the left, with the Downloads shortcut pinned
    // top-right — Home has no app bar, so this stands in for the top control
    // the other pages carry in theirs.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 4, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$greeting  ·  $time'.toUpperCase(),
                  style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 1,
                    color: subtle,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l.navHome,
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                // Opportunistic: only shown when the panel actually reported an
                // expiry date. Month-name + year (e.g. "Jul 17, 2026"), built
                // from MaterialLocalizations so month order and year digits stay
                // locale-aware without pulling in a separate date formatter.
                if (status?.expiresAt != null) ...[
                  const SizedBox(height: 4),
                  Builder(builder: (context) {
                    final m = MaterialLocalizations.of(context);
                    final date =
                        '${m.formatShortMonthDay(status!.expiresAt!)}, ${m.formatYear(status!.expiresAt!)}';
                    return Text(
                      l.accountExpires(date),
                      style: TextStyle(fontSize: 12, color: subtle),
                    );
                  }),
                ],
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: l.customizeHome,
            onPressed: onCustomize,
          ),
          DownloadsButton(account: account),
        ],
      ),
    );
  }
}

class _QuickCards extends StatelessWidget {
  final int? channelCount;
  final Set<ContentType> availableTypes;
  final VoidCallback onOpenLiveTv;
  final VoidCallback onOpenMovies;
  final VoidCallback onOpenSeries;

  const _QuickCards({
    required this.channelCount,
    required this.availableTypes,
    required this.onOpenLiveTv,
    required this.onOpenMovies,
    required this.onOpenSeries,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    // One card per available content type. A card is Expanded so a shorter row
    // (e.g. a channels-only M3U playlist) still fills the width.
    final cards = <Widget>[
      if (availableTypes.contains(ContentType.live))
        _QuickCard(
          icon: Icons.live_tv,
          title: l.navLiveTv,
          // Show the channel count here when it's known (opportunistic),
          // otherwise the generic description.
          subtitle: (channelCount != null && channelCount! > 0)
              ? l.channelsCount(channelCount!)
              : l.quickCardLiveTv,
          onTap: onOpenLiveTv,
        ),
      if (availableTypes.contains(ContentType.movie))
        _QuickCard(
          icon: Icons.movie,
          title: l.navMovies,
          subtitle: l.quickCardMovies,
          onTap: onOpenMovies,
        ),
      if (availableTypes.contains(ContentType.series))
        _QuickCard(
          icon: Icons.video_library,
          title: l.navSeries,
          subtitle: l.quickCardSeries,
          onTap: onOpenSeries,
        ),
    ];
    if (cards.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [for (final card in cards) Expanded(child: card)],
      ),
    );
  }
}

class _QuickCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _QuickCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      color: scheme.surfaceContainerHighest,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Tinted chip behind the icon so the cards read as navigation
              // targets rather than more content tiles.
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: scheme.onPrimaryContainer, size: 20),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(fontSize: 11, color: scheme.outline),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
