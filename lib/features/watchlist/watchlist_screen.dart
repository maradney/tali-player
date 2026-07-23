import 'package:flutter/material.dart';

import '../../data/models/account.dart';
import '../../data/models/favorite_item.dart';
import '../../data/models/movie.dart';
import '../../data/models/series_item.dart';
import '../../data/services/pin_lock_service.dart';
import '../../data/services/playback_service.dart';
import '../../data/services/settings_service.dart';
import '../../data/services/kids_filter_service.dart';
import '../../data/services/watchlist_service.dart';
import '../../l10n/app_localizations.dart';
import '../common/downloads_button.dart';
import '../common/pin_dialogs.dart';
import '../common/poster_grid.dart';
import '../movies/movie_detail_screen.dart';
import '../series/series_detail_screen.dart';

/// The "watch later" queue — movies and series the user saved to get to,
/// distinct from Favorites and Watch History. Same tabbed-poster-grid shape as
/// Favorites/History so it feels like part of the same family. Most recently
/// added shows first (the stored list is oldest-first; we reverse for display).
class WatchlistScreen extends StatefulWidget {
  final Account account;

  const WatchlistScreen({super.key, required this.account});

  @override
  State<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends State<WatchlistScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  bool _isLocked(FavoriteItem item) => PinLockService.instance
      .isLocked(item.type, item.id, categoryId: item.categoryId);

  Future<void> _open(FavoriteItem item) async {
    if (_isLocked(item)) {
      final ok = await requirePin(context,
          title: AppLocalizations.of(context)!.enterPinToOpen(item.name));
      if (!ok) return;
    }
    if (!mounted) return;
    switch (item.type) {
      case 'movie':
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
        break;
      case 'series':
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
        break;
    }
  }

  /// Removes an item, with an Undo so an accidental tap is recoverable.
  void _remove(FavoriteItem item) {
    WatchlistService.instance.toggle(item); // present -> removed
    final l = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(l.removedFromWatchlist(item.name)),
          action: SnackBarAction(
            label: l.undo,
            onPressed: () => WatchlistService.instance.toggle(item),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.watchlistTitle),
        actions: [DownloadsButton(account: widget.account)],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: l.tabAll),
            Tab(text: l.tabMovies),
            Tab(text: l.tabSeries),
          ],
        ),
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge([
          WatchlistService.instance,
          PlaybackService.instance,
          PinLockService.instance,
          SettingsService.instance, // grid density
        ]),
        builder: (context, _) {
          // Newest-added first: the stored list appends on add. In a kids
          // profile, drop items whose category is no longer allowed (no-op
          // otherwise).
          final all = WatchlistService.instance.items.reversed
              .where((i) => !KidsFilterService.instance
                  .isHiddenForItem(i.type, i.id, categoryId: i.categoryId))
              .toList();
          return TabBarView(
            controller: _tabController,
            children: [
              _buildGrid(all),
              _buildGrid(all.where((i) => i.type == 'movie').toList()),
              _buildGrid(all.where((i) => i.type == 'series').toList()),
            ],
          );
        },
      ),
    );
  }

  Widget _buildGrid(List<FavoriteItem> items) {
    if (items.isEmpty) {
      return Center(child: Text(AppLocalizations.of(context)!.noWatchlistItems));
    }
    return PosterGrid<FavoriteItem>(
      items: items,
      idealTileWidth: SettingsService.instance.gridIdealTileWidth,
      titleOf: (i) => i.name,
      posterUrlOf: (i) => i.imageUrl,
      onTap: _open,
      onRemove: _remove,
      onLongPress: _remove,
      ratingOf: (i) => i.extra['rating'] as String?,
      progressFraction: (i) =>
          PlaybackService.instance.progressFraction(i.type, i.id),
      isLocked: _isLocked,
    );
  }
}
