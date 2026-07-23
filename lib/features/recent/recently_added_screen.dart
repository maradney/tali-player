import 'package:flutter/material.dart';

import '../../data/api/xtream_api_service.dart';
import '../../data/db/catalog_database.dart';
import '../../data/models/account.dart';
import '../../data/models/catalog_row.dart';
import '../../data/models/favorite_item.dart';
import '../../data/models/movie.dart';
import '../../data/models/search_result.dart';
import '../../data/models/series_item.dart';
import '../../data/services/catalog_sync_service.dart';
import '../../data/services/favorites_service.dart';
import '../../data/services/kids_filter_service.dart';
import '../../data/services/pin_lock_service.dart';
import '../../data/services/playback_service.dart';
import '../../data/services/settings_service.dart';
import '../../data/services/watchlist_service.dart';
import '../../l10n/app_localizations.dart';
import '../common/downloads_button.dart';
import '../common/grid_density_button.dart';
import '../common/pin_dialogs.dart';
import '../common/poster_grid.dart';
import '../movies/movie_detail_screen.dart';
import '../series/series_detail_screen.dart';

/// The newest movies and series the provider has added to the panel, read
/// straight from the offline catalog index (no extra API calls) ordered by
/// the panel's "added"/"last_modified" date. Same tabbed poster-grid shape as
/// Favorites/Watch History; Live is excluded (channels carry no added date).
class RecentlyAddedScreen extends StatefulWidget {
  final Account account;
  const RecentlyAddedScreen({super.key, required this.account});

  @override
  State<RecentlyAddedScreen> createState() => _RecentlyAddedScreenState();
}

class _RecentlyAddedScreenState extends State<RecentlyAddedScreen>
    with SingleTickerProviderStateMixin {
  final _api = XtreamApiService();
  late final TabController _tabController;
  late final String _accountKey = CatalogRow.accountKeyFor(widget.account);

  // Results per tab index (0 = All, 1 = Movies, 2 = Series).
  final Map<int, List<SearchResult>> _results = {};

  static const _tabTypes = <ContentType?>[
    null, // All (movies + series)
    ContentType.movie,
    ContentType.series,
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    // Keep the list current as the background sync fills/refreshes the index.
    CatalogSyncService.instance.addListener(_onSyncChanged);
    CatalogSyncService.instance.hydrateIndexedTypes(widget.account);
    _load();
  }

  @override
  void dispose() {
    CatalogSyncService.instance.removeListener(_onSyncChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onSyncChanged() {
    if (!mounted) return;
    setState(() {});
    _load();
  }

  Future<void> _load() async {
    for (var i = 0; i < _tabTypes.length; i++) {
      final rows = await CatalogDatabase.instance
          .recentlyAdded(_accountKey, type: _tabTypes[i]);
      if (!mounted) return;
      _results[i] = rows.map((r) => r.toSearchResult()).toList();
    }
    if (mounted) setState(() {});
  }

  bool _tabReady(int index) {
    final sync = CatalogSyncService.instance;
    switch (index) {
      case 1:
        return sync.isTypeIndexed(widget.account, ContentType.movie);
      case 2:
        return sync.isTypeIndexed(widget.account, ContentType.series);
      default: // All needs both movies and series indexed
        return sync.isTypeIndexed(widget.account, ContentType.movie) &&
            sync.isTypeIndexed(widget.account, ContentType.series);
    }
  }

  String _tabLabel(int index, AppLocalizations l) {
    switch (index) {
      case 1:
        return l.tabMovies;
      case 2:
        return l.tabSeries;
      default:
        return l.tabAll;
    }
  }

  bool _isLocked(SearchResult r) => PinLockService.instance
      .isLocked(r.type.name, r.id, categoryId: r.categoryId);

  FavoriteItem _favoriteFor(SearchResult r) {
    if (r.type == ContentType.movie) {
      final Movie m = r.raw;
      return FavoriteItem(
        type: 'movie',
        id: m.streamId,
        name: m.name,
        imageUrl: m.posterUrl,
        categoryId: m.categoryId,
        extra: {
          'containerExtension': m.containerExtension,
          if (m.rating != null) 'rating': m.rating,
        },
      );
    }
    final SeriesItem s = r.raw;
    return FavoriteItem(
      type: 'series',
      id: s.seriesId,
      name: s.name,
      imageUrl: s.coverUrl,
      categoryId: s.categoryId,
      extra: {if (s.rating != null) 'rating': s.rating},
    );
  }

  Future<void> _open(SearchResult r) async {
    if (_isLocked(r)) {
      final ok = await requirePin(context,
          title: AppLocalizations.of(context)!.enterPinToOpen(r.name));
      if (!ok) return;
    }
    if (!mounted) return;
    switch (r.type) {
      case ContentType.movie:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                MovieDetailScreen(account: widget.account, movie: r.raw),
          ),
        );
        break;
      case ContentType.series:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                SeriesDetailScreen(account: widget.account, series: r.raw),
          ),
        );
        break;
      case ContentType.live:
        break; // never happens - live is excluded from Recently Added
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final syncing = CatalogSyncService.instance.isSyncing;
    final disabledColor = Theme.of(context).disabledColor;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.recentlyAddedTitle),
        actions: [
          const GridDensityButton(),
          DownloadsButton(account: widget.account),
          if (syncing)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: l.refreshIndexNow,
              onPressed: () async {
                try {
                  await CatalogSyncService.instance
                      .fullSync(widget.account, _api);
                } catch (_) {
                  // Silent - the list still shows whatever's already indexed.
                }
              },
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            for (var i = 0; i < 3; i++)
              Tab(
                child: Text(
                  _tabLabel(i, l),
                  style: _tabReady(i) ? null : TextStyle(color: disabledColor),
                ),
              ),
          ],
        ),
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge([
          FavoritesService.instance,
          WatchlistService.instance,
          PlaybackService.instance,
          PinLockService.instance,
          SettingsService.instance,
        ]),
        builder: (context, _) => TabBarView(
          controller: _tabController,
          children: [
            for (var i = 0; i < 3; i++) _buildTab(i, l, disabledColor, syncing),
          ],
        ),
      ),
    );
  }

  Widget _buildTab(
      int index, AppLocalizations l, Color disabledColor, bool syncing) {
    if (!_tabReady(index)) {
      return Center(
        child: Text(
          syncing
              ? l.buildingIndexFirstTime
              : l.stillIndexingTab(_tabLabel(index, l)),
          textAlign: TextAlign.center,
          style: TextStyle(color: disabledColor),
        ),
      );
    }
    // Drop anything in a locked *category* — that content is hidden wholesale,
    // not merely gated on open. Individually-locked items stay (shown obscured,
    // PIN on open). Reactive: this runs inside the PinLockService-listening
    // AnimatedBuilder, so unlocking a category brings its titles back.
    final items = (_results[index] ?? const <SearchResult>[])
        .where((r) => !PinLockService.instance.isCategoryLockedForItem(
                r.type.name, r.id, categoryId: r.categoryId) &&
            !KidsFilterService.instance
                .isHiddenForItem(r.type.name, r.id, categoryId: r.categoryId))
        .toList();
    if (items.isEmpty) {
      return Center(
        child: Text(l.noRecentlyAdded, style: TextStyle(color: disabledColor)),
      );
    }
    return PosterGrid<SearchResult>(
      items: items,
      idealTileWidth: SettingsService.instance.gridIdealTileWidth,
      titleOf: (r) => r.name,
      posterUrlOf: (r) => r.imageUrl,
      ratingOf: (r) => r.rating,
      onTap: _open,
      isLocked: _isLocked,
      isFavorite: (r) =>
          FavoritesService.instance.isFavorite(r.type.name, r.id),
      onToggleFavorite: (r) =>
          FavoritesService.instance.toggle(_favoriteFor(r)),
      isInWatchlist: (r) =>
          WatchlistService.instance.isInWatchlist(r.type.name, r.id),
      onToggleWatchlist: (r) =>
          WatchlistService.instance.toggle(_favoriteFor(r)),
      progressFraction: (r) =>
          PlaybackService.instance.progressFraction(r.type.name, r.id),
    );
  }
}
