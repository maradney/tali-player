import 'package:flutter/material.dart';

import '../../data/models/account.dart';
import '../../data/models/movie.dart';
import '../../data/models/series_item.dart';
import '../../data/models/watch_history_entry.dart';
import '../../data/services/pin_lock_service.dart';
import '../../data/services/settings_service.dart';
import '../../data/services/kids_filter_service.dart';
import '../../data/services/watch_history_service.dart';
import '../../l10n/app_localizations.dart';
import '../common/browse_sort.dart';
import '../common/downloads_button.dart';
import '../common/grid_density_button.dart';
import '../common/pin_dialogs.dart';
import '../common/poster_grid.dart';
import '../common/sort_filter_button.dart';
import '../movies/movie_detail_screen.dart';
import '../series/series_detail_screen.dart';

/// Chronological "what did I watch" log, distinct from the continue-watching
/// progress bars scattered across grids/favorites/search - this shows
/// everything opened, most recently watched first, regardless of whether
/// it was finished or a resume position still exists for it. Same
/// tabbed-poster-grid shape as FavoritesScreen/Movies/Series so it feels
/// like part of the same family rather than a bolted-on list.
class WatchHistoryScreen extends StatefulWidget {
  final Account account;

  const WatchHistoryScreen({super.key, required this.account});

  @override
  State<WatchHistoryScreen> createState() => _WatchHistoryScreenState();
}

class _WatchHistoryScreenState extends State<WatchHistoryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // Session-only ordering. History stores no rating, so there's no rating
  // sort/filter; the default is the natural chronological "recently watched".
  static const _sorts = [
    BrowseSort.providerDefault,
    BrowseSort.nameAsc,
    BrowseSort.nameDesc,
  ];
  BrowseSort _sort = BrowseSort.providerDefault;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _clearAll(BuildContext context) async {
    final l = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l.clearHistoryTitle),
        content: Text(l.clearHistoryBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.clearAction),
          ),
        ],
      ),
    );
    if (confirmed == true) await WatchHistoryService.instance.clear();
  }

  Future<void> _confirmRemove(BuildContext context, WatchHistoryEntry entry) async {
    // For a show (episode entry), removing clears every episode of it, since
    // the Series tab shows one tile per show. Movies are a single entry.
    final isSeries = entry.type == 'episode' && entry.seriesId != null;
    final l = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l.removeFromHistoryTitle),
        content: Text(
          isSeries
              ? l.removeSeriesHistoryBody(entry.name)
              : l.removeHistoryBody(entry.name),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.remove),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (isSeries) {
      await WatchHistoryService.instance.removeSeries(entry.seriesId!);
    } else {
      await WatchHistoryService.instance.remove(entry.key);
    }
  }

  // History entries are logged per-episode ('episode'), but locks on
  // series are keyed by 'series' + seriesId (how the Series screen locks
  // them) - translate before checking. Item lock OR category lock; the
  // stored categoryId may be null for older entries, in which case the
  // service falls back to the catalog index.
  bool _isLocked(WatchHistoryEntry entry) {
    final lockType = entry.type == 'episode' ? 'series' : entry.type;
    final lockId = entry.type == 'episode' ? (entry.seriesId ?? entry.id) : entry.id;
    return PinLockService.instance
        .isLocked(lockType, lockId, categoryId: entry.categoryId);
  }

  /// Whether a kids profile's allowlist hides this entry — removed outright,
  /// unlike a lock. Episodes map to their series (how the allowlist keys them);
  /// no-op when the filter is disabled.
  bool _kidsHidden(WatchHistoryEntry entry) {
    final type = entry.type == 'episode' ? 'series' : entry.type;
    final id = entry.type == 'episode' ? (entry.seriesId ?? entry.id) : entry.id;
    return KidsFilterService.instance
        .isHiddenForItem(type, id, categoryId: entry.categoryId);
  }

  Future<void> _openEntry(BuildContext context, WatchHistoryEntry entry) async {
    if (_isLocked(entry)) {
      final ok = await requirePin(context,
          title: AppLocalizations.of(context)!.enterPinToOpen(entry.name));
      if (!ok) return;
    }
    if (!context.mounted) return;
    switch (entry.type) {
      case 'movie':
        final movie = Movie(
          streamId: entry.id,
          name: entry.name,
          categoryId: entry.categoryId ?? '',
          containerExtension: entry.extra['containerExtension'] as String? ?? 'mp4',
          posterUrl: entry.imageUrl,
        );
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MovieDetailScreen(account: widget.account, movie: movie),
          ),
        );
        break;

      case 'episode':
        final series = SeriesItem(
          seriesId: entry.seriesId ?? entry.id,
          name: entry.name,
          categoryId: entry.categoryId ?? '',
          coverUrl: entry.imageUrl,
        );
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SeriesDetailScreen(account: widget.account, series: series),
          ),
        );
        break;
    }
  }

  /// Episodes are logged per-episode, but the grid shows one tile per show
  /// (like the Series screen) - collapse to the most recently watched
  /// episode per seriesId rather than showing a repeat tile per episode.
  List<WatchHistoryEntry> _dedupeSeries(List<WatchHistoryEntry> episodeEntries) {
    final bySeries = <String, WatchHistoryEntry>{};
    for (final e in episodeEntries) {
      final key = e.seriesId ?? e.id;
      final existing = bySeries[key];
      if (existing == null || e.watchedAt.isAfter(existing.watchedAt)) {
        bySeries[key] = e;
      }
    }
    final result = bySeries.values.toList()
      ..sort((a, b) => b.watchedAt.compareTo(a.watchedAt));
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.watchHistoryTitle),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: l.tabMovies),
            Tab(text: l.tabSeries),
          ],
        ),
        actions: [
          SortFilterButton(
            sort: _sort,
            sorts: _sorts,
            defaultSortLabel: l.sortRecentlyWatched,
            onSortChanged: (s) => setState(() => _sort = s),
          ),
          const GridDensityButton(),
          DownloadsButton(account: widget.account),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: l.clearHistoryTooltip,
            onPressed: () => _clearAll(context),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge([
          WatchHistoryService.instance,
          PinLockService.instance,
          SettingsService.instance,
        ]),
        builder: (context, _) {
          final all = WatchHistoryService.instance.entries;
          final movies = all.where((e) => e.type == 'movie').toList();
          final series = _dedupeSeries(all.where((e) => e.type == 'episode').toList());

          return TabBarView(
            controller: _tabController,
            children: [
              _buildGrid(context, movies),
              _buildGrid(context, series),
            ],
          );
        },
      ),
    );
  }

  Widget _buildGrid(BuildContext context, List<WatchHistoryEntry> rawEntries) {
    final entries = rawEntries.where((e) => !_kidsHidden(e)).toList();
    if (entries.isEmpty) {
      return Center(child: Text(AppLocalizations.of(context)!.nothingWatchedYet));
    }
    // entries arrive most-recently-watched first; providerDefault keeps that,
    // the name options re-sort. No rating data, so addedAt/rating go unused.
    final ordered = sortBrowseItems(
      entries,
      sort: _sort,
      nameOf: (e) => e.name,
      ratingOf: (_) => null,
      addedAtOf: (e) => e.watchedAt.millisecondsSinceEpoch,
    );
    return PosterGrid<WatchHistoryEntry>(
      items: ordered,
      idealTileWidth: SettingsService.instance.gridIdealTileWidth,
      titleOf: (e) => e.name,
      posterUrlOf: (e) => e.imageUrl,
      onTap: (e) => _openEntry(context, e),
      onLongPress: (e) => _confirmRemove(context, e),
      onRemove: (e) => _confirmRemove(context, e),
      isLocked: _isLocked,
    );
  }
}
