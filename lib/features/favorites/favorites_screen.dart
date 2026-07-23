import 'package:flutter/material.dart';

import '../../data/models/account.dart';
import '../../data/models/channel.dart';
import '../../data/models/favorite_item.dart';
import '../../data/models/movie.dart';
import '../../data/models/series_item.dart';
import '../../data/services/favorites_service.dart';
import '../../data/services/kids_filter_service.dart';
import '../../data/services/pin_lock_service.dart';
import '../../data/services/playback_service.dart';
import '../../data/sources/media_source.dart';
import '../../l10n/app_localizations.dart';
import '../common/browse_sort.dart';
import '../common/cached_poster_image.dart';
import '../common/continue_watching_bar.dart';
import '../common/downloads_button.dart';
import '../common/pin_dialogs.dart';
import '../common/sort_filter_button.dart';
import '../movies/movie_detail_screen.dart';
import '../player/channel_player_screen.dart';
import '../series/series_detail_screen.dart';

class FavoritesScreen extends StatefulWidget {
  final Account account;
  const FavoritesScreen({super.key, required this.account});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final _source = MediaSource.forAccount(widget.account);

  // Session-only ordering + rating filter, applied to whichever tab is shown.
  // "Recently added" is intentionally omitted — favorites carry no timestamp;
  // the default order is simply the order they were added.
  static const _sorts = [
    BrowseSort.providerDefault,
    BrowseSort.nameAsc,
    BrowseSort.nameDesc,
    BrowseSort.ratingDesc,
  ];
  BrowseSort _sort = BrowseSort.providerDefault;
  double _minRating = 0;

  @override
  void initState() {
    super.initState();
    // Default to "Movies" tab (index 2: All=0, Live=1, Movies=2, Series=3)
    _tabController = TabController(length: 4, vsync: this, initialIndex: 2);
  }

  /// Applies the rating filter then the chosen sort. Live favorites carry no
  /// rating, so a rating filter naturally excludes them — expected on the
  /// Movies/Series tabs, and consistent on the All/Live tabs.
  List<FavoriteItem> _arrange(List<FavoriteItem> items) {
    // In a kids profile, drop favorites whose category is no longer allowed
    // (e.g. the parent removed it after the item was saved) — no-op otherwise.
    final visible = items
        .where((i) => !KidsFilterService.instance
            .isHiddenForItem(i.type, i.id, categoryId: i.categoryId))
        .toList();
    final filtered = filterByMinRating(visible, _minRating,
        ratingOf: (i) => i.extra['rating'] as String?);
    return sortBrowseItems(
      filtered,
      sort: _sort,
      nameOf: (i) => i.name,
      ratingOf: (i) => i.extra['rating'] as String?,
      addedAtOf: (_) => null,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.favoritesTitle),
        actions: [
          SortFilterButton(
            sort: _sort,
            sorts: _sorts,
            minRating: _minRating,
            onSortChanged: (s) => setState(() => _sort = s),
            onMinRatingChanged: (r) => setState(() => _minRating = r),
          ),
          DownloadsButton(account: widget.account),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: l.tabAll),
            Tab(text: l.tabLive),
            Tab(text: l.tabMovies),
            Tab(text: l.tabSeries),
          ],
        ),
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge([
          FavoritesService.instance,
          PlaybackService.instance,
          PinLockService.instance,
        ]),
        builder: (context, _) {
          final allItems = FavoritesService.instance.items;
          return TabBarView(
            controller: _tabController,
            children: [
              _buildList(_arrange(allItems)), // All - mixed types, no reorder
              _buildList(
                  _arrange(allItems.where((i) => i.type == 'live').toList()),
                  reorderType: 'live'),
              _buildList(
                  _arrange(allItems.where((i) => i.type == 'movie').toList()),
                  reorderType: 'movie'),
              _buildList(
                  _arrange(allItems.where((i) => i.type == 'series').toList()),
                  reorderType: 'series'),
            ],
          );
        },
      ),
    );
  }

  Widget _buildList(List<FavoriteItem> items, {String? reorderType}) {
    if (items.isEmpty) {
      return Center(
        child: Text(AppLocalizations.of(context)!.noFavoritesInSection),
      );
    }
    // Manual drag-reorder only makes sense on a single-type tab showing the
    // true stored order — not on the mixed "All" tab, and not while a sort or
    // rating filter is reshaping the list (a drag would fight the sort).
    final canReorder = reorderType != null &&
        _sort == BrowseSort.providerDefault &&
        _minRating == 0;
    if (canReorder) {
      return ReorderableListView.builder(
        itemCount: items.length,
        // onReorderItem already reports newIndex as the post-removal target,
        // which is exactly what FavoritesService.reorder expects.
        onReorderItem: (oldIndex, newIndex) =>
            FavoritesService.instance.reorder(reorderType, oldIndex, newIndex),
        itemBuilder: (context, index) =>
            _favoriteRow(items[index], dragIndex: index),
      );
    }
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) => _favoriteRow(items[index]),
    );
  }

  /// One favorites row. When [dragIndex] is non-null the row is part of a
  /// ReorderableListView and gets a trailing drag handle (mouse-friendly on
  /// desktop). Every row carries a stable key so reordering animates correctly.
  Widget _favoriteRow(FavoriteItem item, {int? dragIndex}) {
    final fraction =
        PlaybackService.instance.progressFraction(item.type, item.id);
    final rating = item.extra['rating'] as String?;
    final locked = _isLocked(item);
    // Not a ListTile: ListTile internally clamps its leading widget to
    // a fixed max height (~56-64px) regardless of the size we ask for,
    // which squished a 56x84 (2:3) thumbnail back toward square. A
    // plain Row sidesteps that constraint entirely.
    return InkWell(
      key: ValueKey(item.key),
      onTap: () => _openItem(context, item),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 56,
              height: 84, // 2:3 poster ratio, matches the grid screens
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: item.imageUrl != null
                          ? CachedPosterImage(
                              imageUrl: item.imageUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const Icon(Icons.image_not_supported),
                            )
                          : const Icon(Icons.image_not_supported),
                    ),
                    if (fraction != null)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: ContinueWatchingBar(fraction: fraction, height: 3),
                      ),
                    if (locked)
                      Positioned.fill(
                        child: Container(
                          color: Colors.black54,
                          child: const Center(
                            child: Icon(Icons.lock,
                                color: Colors.white, size: 20),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (rating != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star, color: Colors.amber, size: 14),
                        const SizedBox(width: 4),
                        Text(rating),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.star, color: Colors.amber),
              onPressed: () => FavoritesService.instance.toggle(item),
            ),
            if (dragIndex != null)
              ReorderableDragStartListener(
                index: dragIndex,
                child: Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Icon(Icons.drag_handle,
                      color: Theme.of(context).disabledColor),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Item lock OR category lock - a favorite snapshotted from a since-locked
  // category must stay blocked. The snapshot's categoryId may be null for
  // favorites saved before it was tracked; the service falls back to the
  // catalog index in that case.
  bool _isLocked(FavoriteItem item) => PinLockService.instance
      .isLocked(item.type, item.id, categoryId: item.categoryId);

  Future<void> _openItem(BuildContext context, FavoriteItem item) async {
    if (_isLocked(item)) {
      final ok = await requirePin(context,
          title: AppLocalizations.of(context)!.enterPinToOpen(item.name));
      if (!ok) return;
    }
    if (!context.mounted) return;
    switch (item.type) {
      case 'live':
        // The favorite is a bare snapshot; resolveChannel re-reads the M3U
        // catalog so the channel gets its playable URL (and any headers)
        // back. Identity for Xtream.
        final channel = await _source.resolveChannel(Channel(
          streamId: item.id,
          name: item.name,
          categoryId: item.categoryId ?? '',
          logoUrl: item.imageUrl,
        ));
        final url = _source.liveUrl(channel);
        if (!context.mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChannelPlayerScreen(
              title: channel.name,
              streamUrl: url,
              httpHeaders:
                  iptvStreamHeaders(channel, isM3u: widget.account.isM3u),
              // Live channel: supply EPG so the now/next strip shows, same
              // as opening it from Live TV or Search.
              epgFuture: _source.getShortEpg(channel.streamId),
              favoriteItem: item,
            ),
          ),
        );
        break;

      case 'movie':
        final movie = Movie(
          streamId: item.id,
          name: item.name,
          categoryId: item.categoryId ?? '',
          containerExtension: item.extra['containerExtension'] as String? ?? 'mp4',
          posterUrl: item.imageUrl,
        );
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MovieDetailScreen(account: widget.account, movie: movie),
          ),
        );
        break;

      case 'series':
        final series = SeriesItem(
          seriesId: item.id,
          name: item.name,
          categoryId: item.categoryId ?? '',
          coverUrl: item.imageUrl,
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
}