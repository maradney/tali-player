import 'package:flutter/material.dart';

import '../../data/db/catalog_database.dart';
import '../../data/models/account.dart';
import '../../data/models/category.dart';
import '../../data/models/favorite_item.dart';
import '../../data/models/movie.dart';
import '../../data/models/search_result.dart';
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
import '../common/category_pane.dart';
import '../common/downloads_button.dart';
import '../common/grid_density_button.dart';
import '../common/pin_dialogs.dart';
import '../common/poster_grid.dart';
import '../common/quick_filter_field.dart';
import '../common/sort_filter_button.dart';
import 'movie_detail_screen.dart';

class MoviesScreen extends StatefulWidget {
  final Account account;

  const MoviesScreen({super.key, required this.account});

  @override
  State<MoviesScreen> createState() => _MoviesScreenState();
}

class _MoviesScreenState extends State<MoviesScreen> {
  late final _source = MediaSource.forAccount(widget.account);

  bool _loadingCategories = true;
  bool _loadingMovies = false;
  String? _error;

  List<Category> _categories = [];
  List<Movie> _movies = [];
  Category? _selectedCategory;

  final _categoryFilterController = TextEditingController();
  final _filterController = TextEditingController();

  // Session-only ordering + rating filter for the selected category's grid.
  BrowseSort _sort = BrowseSort.providerDefault;
  double _minRating = 0;

  // Lowercased cast/director/genre blob per movie id for the selected
  // category, loaded from the enriched catalog when enhanced search is on, so
  // the quick filter can match people/genre and not just titles. Empty
  // otherwise (or for items not yet enriched).
  Map<String, String> _credits = {};

  List<Category> get _filteredCategories {
    final q = _categoryFilterController.text.trim().toLowerCase();
    if (q.isEmpty) return _categories;
    return _categories
        .where((c) => c.categoryName.toLowerCase().contains(q))
        .toList();
  }

  List<Movie> get _filteredMovies {
    final q = _filterController.text.trim().toLowerCase();
    var result = q.isEmpty
        ? _movies
        : _movies
            .where((m) =>
                m.name.toLowerCase().contains(q) ||
                (_credits[m.streamId]?.contains(q) ?? false))
            .toList();
    result = filterByMinRating(result, _minRating, ratingOf: (m) => m.rating);
    return sortBrowseItems(
      result,
      sort: _sort,
      nameOf: (m) => m.name,
      ratingOf: (m) => m.rating,
      addedAtOf: (m) => m.addedAt,
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
      final categories = await _source.getVodCategories();
      if (!mounted) return;
      setState(() {
        // In a kids profile, categories the allowlist doesn't permit are
        // removed outright (not shown behind a lock) — so they never reach
        // the rail, the initial selection, or the item grid.
        _categories = categories
            .where((c) =>
                !KidsFilterService.instance.isCategoryHidden('movie', c.categoryId))
            .toList();
        _loadingCategories = false;
      });
      if (_categories.isNotEmpty) {
        final firstUnlocked = _categories.firstWhere(
          (c) => !PinLockService.instance.isCategoryLocked('movie', c.categoryId),
          orElse: () => _categories.first,
        );
        if (PinLockService.instance
            .isCategoryLocked('movie', firstUnlocked.categoryId)) {
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
    if (PinLockService.instance.isCategoryLocked('movie', category.categoryId)) {
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
      _loadingMovies = true;
      _movies = [];
      _credits = {};
      _error = null;
    });
    try {
      final movies = await _source.getVodStreams(category.categoryId);
      if (!mounted) return;
      setState(() {
        _movies = movies;
        _loadingMovies = false;
      });
      await _loadCreditsIfEnabled(category.categoryId);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = describeApiError(e, widget.account, AppLocalizations.of(context)!);
        _loadingMovies = false;
      });
    }
  }

  /// Loads the enriched cast/director/genre index for one category so the
  /// quick filter can match it. Only when enhanced search is on; a no-op (and
  /// leaves the filter title-only) otherwise or before the crawl reaches these
  /// items.
  Future<void> _loadCreditsIfEnabled(String categoryId) async {
    if (!SettingsService.instance.enhancedSearchEnabled) return;
    final credits = await CatalogDatabase.instance.creditsFor(
      widget.account.key,
      ContentType.movie,
      categoryId: categoryId,
    );
    if (!mounted || _selectedCategory?.categoryId != categoryId) return;
    setState(() => _credits = credits);
  }

  FavoriteItem _favoriteFor(Movie movie) => FavoriteItem(
        type: 'movie',
        id: movie.streamId,
        name: movie.name,
        imageUrl: movie.posterUrl,
        categoryId: movie.categoryId,
        extra: {
          'containerExtension': movie.containerExtension,
          if (movie.rating != null) 'rating': movie.rating,
        },
      );

  Future<void> _openMovie(Movie movie) async {
    if (PinLockService.instance.isItemLocked('movie', movie.streamId)) {
      final ok = await requirePin(context,
          title: AppLocalizations.of(context)!.enterPinToOpen(movie.name));
      if (!ok) return;
    }
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MovieDetailScreen(account: widget.account, movie: movie),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.moviesTitle),
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
                    CategoryPaneFilters(
                      categoryFilter: QuickFilterField(
                        controller: _categoryFilterController,
                        hintText: l.filterCategories,
                      ),
                      itemFilter: QuickFilterField(
                        controller: _filterController,
                        hintText: l.filterMovies,
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: AnimatedBuilder(
                        animation: PinLockService.instance,
                        builder: (context, _) => CategoryPaneLayout(
                          categories: _filteredCategories,
                          selected: _selectedCategory,
                          onSelect: _onCategoryTap,
                          isLocked: (c) => PinLockService.instance
                              .isCategoryLocked('movie', c.categoryId),
                          onLongPress: (c) => toggleCategoryLockPrompt(
                            context,
                            type: 'movie',
                            categoryId: c.categoryId,
                            name: c.categoryName,
                          ),
                          child: _loadingMovies
                                ? const Center(child: CircularProgressIndicator())
                                : _selectedCategory != null &&
                                        _movies.isEmpty &&
                                        PinLockService.instance.isCategoryLocked(
                                            'movie', _selectedCategory!.categoryId)
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
                                    : _filteredMovies.isEmpty
                                        ? Center(
                                            child: Text(l.noMatchingMovies))
                                        : AnimatedBuilder(
                                            animation: Listenable.merge([
                                              FavoritesService.instance,
                                              WatchlistService.instance,
                                              PlaybackService.instance,
                                              PinLockService.instance,
                                              SettingsService.instance,
                                            ]),
                                            builder: (context, _) =>
                                                PosterGrid<Movie>(
                                              items: _filteredMovies,
                                              idealTileWidth: SettingsService
                                                  .instance.gridIdealTileWidth,
                                              titleOf: (m) => m.name,
                                              posterUrlOf: (m) => m.posterUrl,
                                              onTap: _openMovie,
                                              onLongPress: (m) =>
                                                  toggleItemLockPrompt(
                                                context,
                                                type: 'movie',
                                                id: m.streamId,
                                                name: m.name,
                                              ),
                                              isFavorite: (m) =>
                                                  FavoritesService.instance
                                                      .isFavorite(
                                                          'movie', m.streamId),
                                              onToggleFavorite: (m) =>
                                                  FavoritesService.instance
                                                      .toggle(_favoriteFor(m)),
                                              isInWatchlist: (m) =>
                                                  WatchlistService.instance
                                                      .isInWatchlist(
                                                          'movie', m.streamId),
                                              onToggleWatchlist: (m) =>
                                                  WatchlistService.instance
                                                      .toggle(_favoriteFor(m)),
                                              progressFraction: (m) =>
                                                  PlaybackService.instance
                                                      .progressFraction(
                                                          'movie', m.streamId),
                                              ratingOf: (m) => m.rating,
                                              isLocked: (m) => PinLockService
                                                  .instance
                                                  .isItemLocked(
                                                      'movie', m.streamId),
                                            ),
                                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

