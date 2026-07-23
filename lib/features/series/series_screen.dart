import 'package:flutter/material.dart';

import '../../data/db/catalog_database.dart';
import '../../data/models/account.dart';
import '../../data/models/category.dart';
import '../../data/models/favorite_item.dart';
import '../../data/models/search_result.dart';
import '../../data/models/series_item.dart';
import '../../data/services/favorites_service.dart';
import '../../data/services/kids_filter_service.dart';
import '../../data/services/pin_lock_service.dart';
import '../../data/services/playback_service.dart';
import '../../data/services/settings_service.dart';
import '../../data/services/watchlist_service.dart';
import '../../data/sources/media_source.dart';
import '../../l10n/app_localizations.dart';
import '../common/api_error_helper.dart';
import '../common/browse_sort.dart';
import '../common/browse_states.dart';
import '../common/category_rail.dart';
import '../common/downloads_button.dart';
import '../common/grid_density_button.dart';
import '../common/pin_dialogs.dart';
import '../common/poster_grid.dart';
import '../common/quick_filter_field.dart';
import '../common/sort_filter_button.dart';
import 'series_detail_screen.dart';

class SeriesScreen extends StatefulWidget {
  final Account account;

  const SeriesScreen({super.key, required this.account});

  @override
  State<SeriesScreen> createState() => _SeriesScreenState();
}

class _SeriesScreenState extends State<SeriesScreen> {
  late final _source = MediaSource.forAccount(widget.account);

  bool _loadingCategories = true;
  bool _loadingSeries = false;
  String? _error;

  List<Category> _categories = [];
  List<SeriesItem> _series = [];
  Category? _selectedCategory;

  final _categoryFilterController = TextEditingController();
  final _filterController = TextEditingController();

  // Session-only ordering + rating filter for the selected category's grid.
  BrowseSort _sort = BrowseSort.providerDefault;
  double _minRating = 0;

  // Lowercased cast/director/genre blob per series id for the selected
  // category, loaded from the enriched catalog when enhanced search is on, so
  // the quick filter can match people/genre and not just titles.
  Map<String, String> _credits = {};

  List<Category> get _filteredCategories {
    final q = _categoryFilterController.text.trim().toLowerCase();
    if (q.isEmpty) return _categories;
    return _categories
        .where((c) => c.categoryName.toLowerCase().contains(q))
        .toList();
  }

  List<SeriesItem> get _filteredSeries {
    final q = _filterController.text.trim().toLowerCase();
    var result = q.isEmpty
        ? _series
        : _series
            .where((s) =>
                s.name.toLowerCase().contains(q) ||
                (_credits[s.seriesId]?.contains(q) ?? false))
            .toList();
    result = filterByMinRating(result, _minRating, ratingOf: (s) => s.rating);
    return sortBrowseItems(
      result,
      sort: _sort,
      nameOf: (s) => s.name,
      ratingOf: (s) => s.rating,
      addedAtOf: (s) => s.addedAt,
    );
  }

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _categoryFilterController.addListener(() {
      if (mounted) setState(() {});
    });
    _filterController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _categoryFilterController.dispose();
    _filterController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    setState(() {
      _loadingCategories = true;
      _error = null;
    });
    try {
      final categories = await _source.getSeriesCategories();
      if (!mounted) return;
      setState(() {
        // Kids allowlist: disallowed categories are removed outright.
        _categories = categories
            .where((c) => !KidsFilterService.instance
                .isCategoryHidden('series', c.categoryId))
            .toList();
        _loadingCategories = false;
      });
      if (_categories.isNotEmpty) {
        final firstUnlocked = _categories.firstWhere(
          (c) => !PinLockService.instance.isCategoryLocked('series', c.categoryId),
          orElse: () => _categories.first,
        );
        if (PinLockService.instance
            .isCategoryLocked('series', firstUnlocked.categoryId)) {
          setState(() => _selectedCategory = firstUnlocked);
        } else {
          _selectCategory(firstUnlocked);
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = describeApiError(e, widget.account, AppLocalizations.of(context)!);
        _loadingCategories = false;
      });
    }
  }

  /// CategoryRail's onSelect - gates locked categories behind a PIN prompt.
  Future<void> _onCategoryTap(Category category) async {
    if (PinLockService.instance.isCategoryLocked('series', category.categoryId)) {
      final ok = await requirePin(context,
          title: AppLocalizations.of(context)!
              .enterPinToView(category.categoryName));
      if (!ok) return;
    }
    await _selectCategory(category);
  }

  Future<void> _selectCategory(Category category) async {
    if (!mounted) return;
    setState(() {
      _selectedCategory = category;
      _loadingSeries = true;
      _series = [];
      _credits = {};
      _error = null;
    });
    try {
      final series = await _source.getSeries(category.categoryId);
      if (!mounted) return;
      setState(() {
        _series = series;
        _loadingSeries = false;
      });
      await _loadCreditsIfEnabled(category.categoryId);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = describeApiError(e, widget.account, AppLocalizations.of(context)!);
        _loadingSeries = false;
      });
    }
  }

  /// Loads the enriched cast/director/genre index for one category so the
  /// quick filter can match it. Only when enhanced search is on; a no-op
  /// otherwise or before the crawl reaches these items.
  Future<void> _loadCreditsIfEnabled(String categoryId) async {
    if (!SettingsService.instance.enhancedSearchEnabled) return;
    final credits = await CatalogDatabase.instance.creditsFor(
      widget.account.key,
      ContentType.series,
      categoryId: categoryId,
    );
    if (!mounted || _selectedCategory?.categoryId != categoryId) return;
    setState(() => _credits = credits);
  }

  FavoriteItem _favoriteFor(SeriesItem series) => FavoriteItem(
        type: 'series',
        id: series.seriesId,
        name: series.name,
        imageUrl: series.coverUrl,
        categoryId: series.categoryId,
        extra: {
          if (series.rating != null) 'rating': series.rating,
        },
      );

  Future<void> _openSeries(SeriesItem series) async {
    if (PinLockService.instance.isItemLocked('series', series.seriesId)) {
      final ok = await requirePin(context,
          title: AppLocalizations.of(context)!.enterPinToOpen(series.name));
      if (!ok) return;
    }
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SeriesDetailScreen(account: widget.account, series: series),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.seriesTitle),
        actions: [
          SortFilterButton(
            sort: _sort,
            minRating: _minRating,
            onSortChanged: (s) => setState(() => _sort = s),
            onMinRatingChanged: (r) => setState(() => _minRating = r),
          ),
          const GridDensityButton(),
          DownloadsButton(account: widget.account),
        ],
      ),
      body: _loadingCategories
          ? LoadingState(message: l.connectingToServer)
          : _error != null && _categories.isEmpty
              ? ErrorState(message: _error!, onRetry: _loadCategories)
              : Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: CategoryRail.width,
                          child: QuickFilterField(
                            controller: _categoryFilterController,
                            hintText: l.filterCategories,
                          ),
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(
                          child: QuickFilterField(
                            controller: _filterController,
                            hintText: l.filterSeries,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: Row(
                        children: [
                          AnimatedBuilder(
                            animation: PinLockService.instance,
                            builder: (context, _) => CategoryRail(
                              categories: _filteredCategories,
                              selected: _selectedCategory,
                              onSelect: _onCategoryTap,
                              isLocked: (c) => PinLockService.instance
                                  .isCategoryLocked('series', c.categoryId),
                              onLongPress: (c) => toggleCategoryLockPrompt(
                                context,
                                type: 'series',
                                categoryId: c.categoryId,
                                name: c.categoryName,
                              ),
                            ),
                          ),
                          const VerticalDivider(width: 1),
                          Expanded(
                            child: _loadingSeries
                                ? const Center(child: CircularProgressIndicator())
                                : _selectedCategory != null &&
                                        _series.isEmpty &&
                                        PinLockService.instance.isCategoryLocked(
                                            'series', _selectedCategory!.categoryId)
                                    ? LockedCategoryPlaceholder(
                                        onUnlock: () =>
                                            _onCategoryTap(_selectedCategory!),
                                      )
                                    : _error != null
                                    ? ErrorState(
                                        message: _error!,
                                        onRetry: () => _selectedCategory != null
                                            ? _selectCategory(_selectedCategory!)
                                            : null,
                                      )
                                    : _filteredSeries.isEmpty
                                        ? Center(
                                            child: Text(l.noMatchingSeries))
                                        : AnimatedBuilder(
                                            animation: Listenable.merge([
                                              FavoritesService.instance,
                                              WatchlistService.instance,
                                              PlaybackService.instance,
                                              PinLockService.instance,
                                              SettingsService.instance,
                                            ]),
                                            builder: (context, _) =>
                                                PosterGrid<SeriesItem>(
                                              items: _filteredSeries,
                                              idealTileWidth: SettingsService
                                                  .instance.gridIdealTileWidth,
                                              titleOf: (s) => s.name,
                                              posterUrlOf: (s) => s.coverUrl,
                                              onTap: _openSeries,
                                              onLongPress: (s) =>
                                                  toggleItemLockPrompt(
                                                context,
                                                type: 'series',
                                                id: s.seriesId,
                                                name: s.name,
                                              ),
                                              isFavorite: (s) =>
                                                  FavoritesService.instance
                                                      .isFavorite('series',
                                                          s.seriesId),
                                              onToggleFavorite: (s) =>
                                                  FavoritesService.instance
                                                      .toggle(_favoriteFor(s)),
                                              isInWatchlist: (s) =>
                                                  WatchlistService.instance
                                                      .isInWatchlist('series',
                                                          s.seriesId),
                                              onToggleWatchlist: (s) =>
                                                  WatchlistService.instance
                                                      .toggle(_favoriteFor(s)),
                                              progressFraction: (s) =>
                                                  PlaybackService.instance
                                                      .progressFraction('series',
                                                          s.seriesId),
                                              ratingOf: (s) => s.rating,
                                              isLocked: (s) => PinLockService
                                                  .instance
                                                  .isItemLocked(
                                                      'series', s.seriesId),
                                            ),
                                          ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}

