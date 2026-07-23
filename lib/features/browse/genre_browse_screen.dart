import 'package:flutter/material.dart';

import '../../data/db/catalog_database.dart';
import '../../data/models/account.dart';
import '../../data/models/catalog_row.dart';
import '../../data/models/favorite_item.dart';
import '../../data/models/search_result.dart';
import '../../data/services/favorites_service.dart';
import '../../data/services/kids_filter_service.dart';
import '../../data/services/pin_lock_service.dart';
import '../../data/services/playback_service.dart';
import '../../data/services/settings_service.dart';
import '../../data/services/watchlist_service.dart';
import '../../l10n/app_localizations.dart';
import '../common/browse_sort.dart';
import '../common/grid_density_button.dart';
import '../common/pin_dialogs.dart';
import '../common/poster_grid.dart';
import '../common/sort_filter_button.dart';
import '../movies/movie_detail_screen.dart';
import '../series/series_detail_screen.dart';

/// The drill-in from the Browse genre landing: every enriched movie/series
/// tagged with one genre, cutting across the panel's categories. Read straight
/// from the offline catalog index (no API calls). Year/rating/sort narrow the
/// list client-side, session-only, just like the Movies/Series grids.
class GenreBrowseScreen extends StatefulWidget {
  final Account account;
  final String genre;

  const GenreBrowseScreen({
    super.key,
    required this.account,
    required this.genre,
  });

  @override
  State<GenreBrowseScreen> createState() => _GenreBrowseScreenState();
}

class _GenreBrowseScreenState extends State<GenreBrowseScreen> {
  late final String _accountKey = CatalogRow.accountKeyFor(widget.account);

  bool _loading = true;
  List<CatalogRow> _items = [];

  // Session-only ordering + filters for this genre's grid.
  BrowseSort _sort = BrowseSort.providerDefault;
  double _minRating = 0;
  int? _year; // null = any year

  /// The loaded items minus anything in a locked *category* — that content is
  /// meant to be hidden wholesale, not just gated on open. Individually-locked
  /// items stay (they show obscured and ask for a PIN on tap). Reactive: it's
  /// read inside the [PinLockService]-listening builder, so unlocking a
  /// category reveals its titles live.
  List<CatalogRow> get _visible => _items
      .where((r) =>
          !PinLockService.instance.isCategoryLockedForItem(r.type.name, r.id,
              categoryId: r.categoryId) &&
          !KidsFilterService.instance
              .isHiddenForItem(r.type.name, r.id, categoryId: r.categoryId))
      .toList();

  /// Distinct release years present in the visible set, newest first, for the
  /// year filter menu. Empty when nothing carries a year yet.
  List<int> get _years {
    final years = _visible.map((r) => r.year).whereType<int>().toSet().toList()
      ..sort((a, b) => b.compareTo(a));
    return years;
  }

  List<CatalogRow> get _filtered {
    var result = _visible;
    if (_year != null) {
      result = result.where((r) => r.year == _year).toList();
    }
    result = filterByMinRating(result, _minRating,
        ratingOf: (r) => r.extra['rating'] as String?);
    return sortBrowseItems(
      result,
      sort: _sort,
      nameOf: (r) => r.name,
      ratingOf: (r) => r.extra['rating'] as String?,
      addedAtOf: (r) => r.addedAt,
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows =
        await CatalogDatabase.instance.byGenre(_accountKey, widget.genre);
    if (!mounted) return;
    setState(() {
      _items = rows;
      _loading = false;
    });
  }

  bool _isLocked(CatalogRow r) => PinLockService.instance
      .isLocked(r.type.name, r.id, categoryId: r.categoryId);

  FavoriteItem _favoriteFor(CatalogRow r) => FavoriteItem(
        type: r.type.name,
        id: r.id,
        name: r.name,
        imageUrl: r.imageUrl,
        categoryId: r.categoryId,
        extra: {
          if (r.type == ContentType.movie)
            'containerExtension':
                r.extra['containerExtension'] as String? ?? 'mp4',
          if (r.extra['rating'] != null) 'rating': r.extra['rating'],
        },
      );

  Future<void> _open(CatalogRow r) async {
    if (_isLocked(r)) {
      final ok = await requirePin(context,
          title: AppLocalizations.of(context)!.enterPinToOpen(r.name));
      if (!ok) return;
    }
    if (!mounted) return;
    final result = r.toSearchResult();
    switch (r.type) {
      case ContentType.movie:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                MovieDetailScreen(account: widget.account, movie: result.raw),
          ),
        );
        break;
      case ContentType.series:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SeriesDetailScreen(
                account: widget.account, series: result.raw),
          ),
        );
        break;
      case ContentType.live:
        break; // live is never indexed into a genre
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.genre),
        actions: [
          SortFilterButton(
            sort: _sort,
            minRating: _minRating,
            onSortChanged: (s) => setState(() => _sort = s),
            onMinRatingChanged: (r) => setState(() => _minRating = r),
          ),
          if (_years.isNotEmpty) _yearButton(l),
          const GridDensityButton(),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(child: Text(l.noItemsInCategory))
              : AnimatedBuilder(
                  animation: Listenable.merge([
                    FavoritesService.instance,
                    WatchlistService.instance,
                    PlaybackService.instance,
                    PinLockService.instance,
                    SettingsService.instance,
                  ]),
                  builder: (context, _) {
                    final items = _filtered;
                    if (items.isEmpty) {
                      return Center(child: Text(l.noItemsInCategory));
                    }
                    return PosterGrid<CatalogRow>(
                      items: items,
                      idealTileWidth:
                          SettingsService.instance.gridIdealTileWidth,
                      titleOf: (r) => r.name,
                      posterUrlOf: (r) => r.imageUrl,
                      ratingOf: (r) => r.extra['rating'] as String?,
                      onTap: _open,
                      onLongPress: (r) => toggleItemLockPrompt(
                        context,
                        type: r.type.name,
                        id: r.id,
                        name: r.name,
                      ),
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
                  },
                ),
    );
  }

  Widget _yearButton(AppLocalizations l) {
    return PopupMenuButton<int?>(
      tooltip: l.filterByYear,
      icon: Icon(_year != null ? Icons.event_available : Icons.event),
      onSelected: (y) => setState(() => _year = y),
      itemBuilder: (context) => [
        CheckedPopupMenuItem(
          value: null,
          checked: _year == null,
          child: Text(l.yearAny),
        ),
        for (final y in _years)
          CheckedPopupMenuItem(
            value: y,
            checked: _year == y,
            child: Text('$y'),
          ),
      ],
    );
  }
}
