import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/api/xtream_api_service.dart';
import '../../data/db/catalog_database.dart';
import '../../data/models/account.dart';
import '../../data/models/catalog_row.dart';
import '../../data/models/channel.dart';
import '../../data/models/favorite_item.dart';
import '../../data/models/search_result.dart';
import '../../data/services/catalog_sync_service.dart';
import '../../data/services/kids_filter_service.dart';
import '../../data/services/pin_lock_service.dart';
import '../../data/services/playback_service.dart';
import '../../data/services/settings_service.dart';
import '../../data/sources/media_source.dart';
import '../../l10n/app_localizations.dart';
import '../common/cached_poster_image.dart';
import '../common/continue_watching_bar.dart';
import '../common/downloads_button.dart';
import '../common/pin_dialogs.dart';
import '../movies/movie_detail_screen.dart';
import '../player/channel_player_screen.dart';
import '../series/series_detail_screen.dart';

/// How many recent search queries to remember per account.
const _maxRecentSearches = 8;

class SearchScreen extends StatefulWidget {
  final Account account;
  const SearchScreen({super.key, required this.account});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with SingleTickerProviderStateMixin {
  // The Xtream API is still used for the background catalog sync below; the
  // source handles per-item playback URLs + EPG so both source kinds work.
  final _api = XtreamApiService();
  late final _source = MediaSource.forAccount(widget.account);
  final _queryController = TextEditingController();
  final _searchFocusNode = FocusNode();
  late final TabController _tabController;

  late final String _accountKey = CatalogRow.accountKeyFor(widget.account);
  String get _recentSearchesPrefsKey => 'recent_searches_v1_$_accountKey';

  // Mixed list of section markers and results - only used to build the
  // list view. Each entry is either a [ContentType] (rendered as a
  // "----Live----" style separator, only appears on the "All" tab) or a
  // [SearchResult].
  List<Object> _results = [];
  int _totalIndexed = 0;
  DateTime? _lastSynced;

  // Per-type match counts for the current query, used for the small
  // "(12)" badges next to each tab label - computed for every type
  // regardless of which tab is selected.
  Map<ContentType, int> _tabCounts = {};

  List<String> _recentSearches = [];

  Timer? _debounce;
  int _searchRequestId = 0; // guards against a slower, stale query result
                             // landing after a faster, newer one

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    // Tab switches are a discrete filter change - rerun immediately,
    // no debounce needed (unlike typing).
    _tabController.addListener(() {
      if (mounted) {
        setState(() {});
        _refreshCounts();
        _runSearch();
      }
    });
    // Keeps the clear button, empty-state, badge counts, and match
    // highlighting live on every keystroke - separate from the debounced
    // _runSearch() below, which only re-queries the database.
    _queryController.addListener(() {
      if (mounted) setState(() {});
    });
    // Reacts to CatalogSyncService's progress/completion - this is what
    // keeps "items indexed"/"Updated" and the per-tab enabled state
    // current no matter which screen actually triggered the sync (login's
    // background kick-off, or the refresh button here).
    CatalogSyncService.instance.addListener(_onSyncServiceChanged);
    CatalogSyncService.instance.hydrateIndexedTypes(widget.account);
    // Locking/unlocking a category changes both the filtered result list (via
    // the PinLockService-listening builder) and the tab-count badges — the
    // badges need an explicit recompute since they're cached in _tabCounts.
    PinLockService.instance.addListener(_onLocksChanged);
    _refreshCounts();
    _loadRecentSearches();
    _backgroundSync(); // idempotent/throttled - safe even if login already triggered one
  }

  @override
  void dispose() {
    _debounce?.cancel();
    CatalogSyncService.instance.removeListener(_onSyncServiceChanged);
    PinLockService.instance.removeListener(_onLocksChanged);
    _tabController.dispose();
    _queryController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  /// A category was locked/unlocked: the result list re-filters itself via the
  /// PinLockService-listening builder, but the cached badge counts don't — so
  /// recompute them here to keep badge numbers matching the visible rows.
  void _onLocksChanged() {
    if (mounted) _refreshTabCounts();
  }

  void _onSyncServiceChanged() {
    if (!mounted) return;
    setState(() {});
    _refreshCounts();
    _runSearch();
    _refreshTabCounts();
  }

  Future<void> _loadRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_recentSearchesPrefsKey) ?? [];
    if (mounted) setState(() => _recentSearches = list);
  }

  Future<void> _saveRecentSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    final updated = [
      trimmed,
      ..._recentSearches.where((s) => s.toLowerCase() != trimmed.toLowerCase()),
    ];
    if (updated.length > _maxRecentSearches) {
      updated.removeRange(_maxRecentSearches, updated.length);
    }
    setState(() => _recentSearches = updated);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_recentSearchesPrefsKey, updated);
  }

  Future<void> _clearRecentSearches() async {
    setState(() => _recentSearches = []);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_recentSearchesPrefsKey);
  }

  void _tapRecentSearch(String query) {
    _queryController.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
    _debounce?.cancel();
    _runSearch();
    _refreshTabCounts();
    _searchFocusNode.requestFocus();
  }

  Future<void> _refreshTabCounts() async {
    final query = _queryController.text.trim();
    if (query.isEmpty) {
      if (mounted) setState(() => _tabCounts = {});
      return;
    }
    final locked = PinLockService.instance.lockedCategoryKeys;
    final allowed = KidsFilterService.instance.allowedCategoryKeysOrNull;
    final counts = <ContentType, int>{};
    for (final t in ContentType.values) {
      if (!CatalogSyncService.instance.isTypeIndexed(widget.account, t)) continue;
      counts[t] = await CatalogDatabase.instance.searchCount(
        _accountKey,
        query,
        type: t,
        matchCredits: _matchCredits,
        lockedCategoryKeys: locked,
        allowedCategoryKeys: allowed,
      );
    }
    if (mounted) setState(() => _tabCounts = counts);
  }

  /// Whether search should also match cast/director/genre — only when the
  /// enhanced-search setting is on (and thus the catalog has been enriched).
  bool get _matchCredits => SettingsService.instance.enhancedSearchEnabled;

  ContentType? get _selectedType {
    switch (_tabController.index) {
      case 1:
        return ContentType.live;
      case 2:
        return ContentType.movie;
      case 3:
        return ContentType.series;
      default:
        return null; // "All"
    }
  }

  /// Whether the currently-selected tab's content is actually searchable
  /// yet - "All" needs every type indexed, a single-type tab just needs
  /// that one.
  bool get _selectedTabReady {
    final type = _selectedType;
    return type == null
        ? CatalogSyncService.instance.isAllIndexed(widget.account)
        : CatalogSyncService.instance.isTypeIndexed(widget.account, type);
  }

  bool _tabReady(int index) {
    switch (index) {
      case 1:
        return CatalogSyncService.instance
            .isTypeIndexed(widget.account, ContentType.live);
      case 2:
        return CatalogSyncService.instance
            .isTypeIndexed(widget.account, ContentType.movie);
      case 3:
        return CatalogSyncService.instance
            .isTypeIndexed(widget.account, ContentType.series);
      default:
        return CatalogSyncService.instance.isAllIndexed(widget.account);
    }
  }

// A tab that isn't indexed yet stays selectable on purpose.
//
// It used to be refused: onTap assigned _tabController.index =
// previousIndex, which fights the TabBar's own animation toward the tapped
// tab. That left three disagreeing ideas of "the current tab" on screen at
// once - the indicator underlined one, the highlighted label sat on another,
// and the body text named a third - because the indicator follows the
// controller's animation, the snackbar named the tapped index, and the body
// named whatever the controller finally settled on. Worse, after one refused
// tap `previousIndex` *is* the refused tab, so the next refusal snapped onto
// it rather than away from it.
//
// Letting the selection through removes the whole class of disagreement:
// there is one source of truth, the tab you picked. The label is already
// greyed out, the field stays disabled, and the body says which section is
// still indexing - which is more informative than a snackbar naming a tab
// you are no longer on.

  String _tabLabel(int index, AppLocalizations l) {
    switch (index) {
      case 1:
        return l.tabLive;
      case 2:
        return l.tabMovies;
      case 3:
        return l.tabSeries;
      default:
        return l.tabAll;
    }
  }

  Future<void> _refreshCounts() async {
    final type = _selectedType;
    final total = await CatalogDatabase.instance.countFor(_accountKey, type: type);
    // "All" is only as fresh as the least-recently-synced type - showing
    // anything else would overstate how current the combined results are.
    DateTime? synced;
    if (type != null) {
      synced = await CatalogDatabase.instance.typeSyncedAt(_accountKey, type);
    } else {
      for (final t in ContentType.values) {
        final t0 = await CatalogDatabase.instance.typeSyncedAt(_accountKey, t);
        if (t0 == null) {
          synced = null;
          break;
        }
        if (synced == null || t0.isBefore(synced)) synced = t0;
      }
    }
    if (mounted) {
      setState(() {
        _totalIndexed = total;
        _lastSynced = synced;
      });
    }
  }

  Future<void> _backgroundSync({bool force = false}) async {
    try {
      if (force) {
        await CatalogSyncService.instance.fullSync(widget.account, _api);
      } else {
        await CatalogSyncService.instance.syncIfNeeded(widget.account, _api);
      }
    } catch (_) {
      // Silent - search still works fine off whatever's already indexed
      // from a previous sync; no need to interrupt the person over this.
    }
  }

  void _onQueryChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      _runSearch();
      _refreshTabCounts();
    });
  }

  void _onQuerySubmitted(String query) {
    _debounce?.cancel();
    _runSearch();
    _refreshTabCounts();
    _saveRecentSearch(query);
  }

  Future<void> _runSearch() async {
    final requestId = ++_searchRequestId;
    final query = _queryController.text.trim();
    if (query.isEmpty || !_selectedTabReady) {
      setState(() => _results = []);
      return;
    }

    final type = _selectedType;
    final items = <Object>[];
    if (type != null) {
      final rows = await CatalogDatabase.instance
          .search(_accountKey, query, type: type, matchCredits: _matchCredits);
      items.addAll(rows.map((r) => r.toSearchResult()));
    } else {
      // "All" - query each type separately (rather than one mixed,
      // alphabetically-interleaved query) so results can be grouped into
      // clearly labeled Live/Movies/Series sections.
      for (final t in ContentType.values) {
        final rows = await CatalogDatabase.instance
            .search(_accountKey, query, type: t, matchCredits: _matchCredits);
        if (rows.isEmpty) continue;
        items.add(t); // section marker
        items.addAll(rows.map((r) => r.toSearchResult()));
      }
    }

    if (requestId != _searchRequestId || !mounted) return; // superseded by a newer query
    setState(() => _results = items);
  }

  String _formatLastSynced(DateTime? time, AppLocalizations l) {
    if (time == null) return l.syncNever;
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return l.syncJustNow;
    if (diff.inMinutes < 60) return l.syncMinutesAgo(diff.inMinutes);
    if (diff.inHours < 24) return l.syncHoursAgo(diff.inHours);
    return l.syncDaysAgo(diff.inDays);
  }

  IconData _iconFor(ContentType type) {
    switch (type) {
      case ContentType.live:
        return Icons.tv;
      case ContentType.movie:
        return Icons.movie;
      case ContentType.series:
        return Icons.video_library;
    }
  }

  String _labelFor(ContentType type, AppLocalizations l) {
    switch (type) {
      case ContentType.live:
        return l.navLiveTv;
      case ContentType.movie:
        return l.contentMovie;
      case ContentType.series:
        return l.navSeries;
    }
  }

  String _sectionLabelFor(ContentType type, AppLocalizations l) {
    switch (type) {
      case ContentType.live:
        return l.tabLive;
      case ContentType.movie:
        return l.tabMovies;
      case ContentType.series:
        return l.tabSeries;
    }
  }

  ContentType? _typeForTabIndex(int index) {
    switch (index) {
      case 1:
        return ContentType.live;
      case 2:
        return ContentType.movie;
      case 3:
        return ContentType.series;
      default:
        return null; // "All"
    }
  }

  /// Match count badge for one tab, or null to show no badge - null while
  /// the query is empty, or for a type whose count hasn't been computed
  /// yet (e.g. still indexing).
  int? _countForTabIndex(int index) {
    if (_queryController.text.trim().isEmpty || _tabCounts.isEmpty) return null;
    final type = _typeForTabIndex(index);
    if (type != null) return _tabCounts[type];
    return _tabCounts.values.fold<int>(0, (a, b) => a + b); // "All"
  }

  String _tabLabelWithCount(int index, AppLocalizations l) {
    final label = _tabLabel(index, l);
    final count = _countForTabIndex(index);
    return count == null ? label : '$label ($count)';
  }

  // Item lock OR category lock.
  bool _isLocked(SearchResult result) => PinLockService.instance
      .isLocked(result.type.name, result.id, categoryId: result.categoryId);

  Future<void> _openResult(SearchResult result) async {
    if (_isLocked(result)) {
      final ok = await requirePin(context,
          title: AppLocalizations.of(context)!.enterPinToOpen(result.name));
      if (!ok) return;
    }
    if (!mounted) return;
    _saveRecentSearch(_queryController.text);
    switch (result.type) {
      case ContentType.live:
        final Channel channel = result.raw;
        final url = _source.liveUrl(channel);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChannelPlayerScreen(
              title: result.name,
              streamUrl: url,
              epgFuture: _source.getShortEpg(result.id),
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
        break;

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
              account: widget.account,
              series: result.raw,
            ),
          ),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final query = _queryController.text.trim();
    final syncing = CatalogSyncService.instance.isSyncing;
    final disabledColor = Theme.of(context).disabledColor;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.searchTitle),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            for (var i = 0; i < 4; i++)
              Tab(
                child: Text(
                  _tabLabelWithCount(i, l),
                  style: _tabReady(i) ? null : TextStyle(color: disabledColor),
                ),
              ),
          ],
        ),
        actions: [
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
              onPressed: () => _backgroundSync(force: true),
            ),
          DownloadsButton(account: widget.account),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              controller: _queryController,
              focusNode: _searchFocusNode,
              autofocus: true,
              enabled: _selectedTabReady,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _queryController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        tooltip: l.clear,
                        onPressed: () {
                          _queryController.clear();
                          _onQueryChanged('');
                        },
                      ),
                hintText: _selectedTabReady
                    ? l.searchHint
                    : l.stillIndexingSection,
                border: const OutlineInputBorder(),
              ),
              onChanged: _onQueryChanged,
              onSubmitted: _onQuerySubmitted,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Text(
                  l.itemsIndexed(_totalIndexed),
                  style: TextStyle(fontSize: 12, color: disabledColor),
                ),
                const Spacer(),
                Text(
                  l.updatedAgo(_formatLastSynced(_lastSynced, l)),
                  style: TextStyle(fontSize: 12, color: disabledColor),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: !_selectedTabReady
                ? Center(
                    child: Text(
                      l.stillIndexingTab(_tabLabel(_tabController.index, l)),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: disabledColor),
                    ),
                  )
                : query.isEmpty
                    ? _EmptyState(
                        hint: _totalIndexed == 0
                            ? (syncing
                                ? l.buildingIndexFirstTime
                                : l.noIndexYet)
                            : l.startTypingToSearch,
                        disabledColor: disabledColor,
                        recentSearches: _recentSearches,
                        onTapRecent: _tapRecentSearch,
                        onClearRecent: _clearRecentSearches,
                      )
                    : _results.isEmpty
                        ? Center(child: Text(l.noMatches))
                        : AnimatedBuilder(
                            animation: Listenable.merge(
                                [PlaybackService.instance, PinLockService.instance]),
                            builder: (context, _) {
                              final visible = _visibleResults;
                              if (visible.isEmpty) {
                                return Center(child: Text(l.noMatches));
                              }
                              return ListView.builder(
                              itemCount: visible.length,
                              itemBuilder: (context, index) {
                                final item = visible[index];
                                if (item is ContentType) {
                                  return _SectionSeparator(
                                    label: _sectionLabelFor(item, l),
                                  );
                                }
                                final result = item as SearchResult;
                                final fraction = PlaybackService.instance
                                    .progressFraction(result.type.name, result.id);
                                final locked = _isLocked(result);
                                return ListTile(
                                  leading: SizedBox(
                                    width: 40,
                                    height: 40,
                                    child: Stack(
                                      children: [
                                        Positioned.fill(
                                          child: result.imageUrl != null
                                              ? CachedPosterImage(
                                                  imageUrl: result.imageUrl!,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (_, __, ___) =>
                                                      Icon(_iconFor(result.type)),
                                                )
                                              : Icon(_iconFor(result.type)),
                                        ),
                                        if (fraction != null)
                                          Positioned(
                                            left: 0,
                                            right: 0,
                                            bottom: 0,
                                            child: ContinueWatchingBar(
                                                fraction: fraction, height: 3),
                                          ),
                                        if (locked)
                                          Positioned.fill(
                                            child: Container(
                                              color: Colors.black54,
                                              child: const Center(
                                                child: Icon(Icons.lock,
                                                    color: Colors.white, size: 18),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  title: _HighlightedText(
                                    text: result.name,
                                    query: query,
                                  ),
                                  subtitle: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(_labelFor(result.type, l)),
                                      if (result.rating != null) ...[
                                        const SizedBox(width: 8),
                                        const Icon(Icons.star,
                                            color: Colors.amber, size: 14),
                                        const SizedBox(width: 2),
                                        Text(result.rating!),
                                      ],
                                    ],
                                  ),
                                  onTap: () => _openResult(result),
                                );
                              },
                            );
                            },
                          ),
          ),
        ],
      ),
    );
  }

  /// [_results] with category-locked rows removed and now-empty section headers
  /// dropped (see [visibleSearchResults]). Computed inside the
  /// PinLockService-listening builder, so locking/unlocking a category updates
  /// the list live. Note: the tab count badges still reflect the raw index.
  List<Object> get _visibleResults => visibleSearchResults(
        _results,
        (r) =>
            PinLockService.instance.isCategoryLockedForItem(r.type.name, r.id,
                categoryId: r.categoryId) ||
            KidsFilterService.instance
                .isHiddenForItem(r.type.name, r.id, categoryId: r.categoryId),
      );
}

/// Filters a flat search-results list — a mix of [ContentType] section markers
/// and [SearchResult] rows — down to what should be shown. Rows whose *category*
/// is locked (per [isCategoryLocked]) are removed, and any section marker left
/// with no result after it is dropped. Item-level locks are intentionally NOT
/// filtered here: those rows stay (shown obscured, PIN on open). Pure so the
/// section-pruning is unit-testable without standing up the screen.
List<Object> visibleSearchResults(
  List<Object> results,
  bool Function(SearchResult) isCategoryLocked,
) {
  final filtered = <Object>[];
  for (final item in results) {
    if (item is ContentType) {
      filtered.add(item); // provisional; pruned below if nothing follows
    } else if (item is SearchResult) {
      if (isCategoryLocked(item)) continue;
      filtered.add(item);
    }
  }
  // Second pass: drop a section marker if it isn't followed by a result.
  final pruned = <Object>[];
  for (var i = 0; i < filtered.length; i++) {
    final item = filtered[i];
    if (item is ContentType &&
        (i + 1 >= filtered.length || filtered[i + 1] is! SearchResult)) {
      continue;
    }
    pruned.add(item);
  }
  return pruned;
}

/// A "----Live----" style section header separating grouped results on
/// the "All" tab.
class _SectionSeparator extends StatelessWidget {
  final String label;
  const _SectionSeparator({required this.label});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          Expanded(child: Divider(color: color.withValues(alpha: 0.4))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
                color: color,
              ),
            ),
          ),
          Expanded(child: Divider(color: color.withValues(alpha: 0.4))),
        ],
      ),
    );
  }
}

/// Shown when the search field is empty - recent searches (if any) as
/// tappable chips, above the usual indexing-status hint text.
class _EmptyState extends StatelessWidget {
  final String hint;
  final Color disabledColor;
  final List<String> recentSearches;
  final ValueChanged<String> onTapRecent;
  final VoidCallback onClearRecent;

  const _EmptyState({
    required this.hint,
    required this.disabledColor,
    required this.recentSearches,
    required this.onTapRecent,
    required this.onClearRecent,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    if (recentSearches.isEmpty) {
      return Center(child: Text(hint, style: TextStyle(color: disabledColor)));
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                l.recentSearches,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                  color: disabledColor,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: onClearRecent,
                child: Text(l.clear),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final q in recentSearches)
                ActionChip(
                  label: Text(q),
                  onPressed: () => onTapRecent(q),
                ),
            ],
          ),
          Expanded(
            child: Center(child: Text(hint, style: TextStyle(color: disabledColor))),
          ),
        ],
      ),
    );
  }
}

/// Bolds+highlights the first case-insensitive match of [query] within
/// [text] - falls back to plain text if there's no match (e.g. it matched
/// on something other than the display name).
class _HighlightedText extends StatelessWidget {
  final String text;
  final String query;

  const _HighlightedText({required this.text, required this.query});

  @override
  Widget build(BuildContext context) {
    if (query.isEmpty) return Text(text);
    final index = text.toLowerCase().indexOf(query.toLowerCase());
    if (index < 0) return Text(text);

    final defaultStyle = DefaultTextStyle.of(context).style;
    final highlightStyle = defaultStyle.copyWith(
      fontWeight: FontWeight.bold,
      backgroundColor:
          Theme.of(context).colorScheme.primary.withValues(alpha: 0.25),
    );
    return Text.rich(
      TextSpan(
        style: defaultStyle,
        children: [
          TextSpan(text: text.substring(0, index)),
          TextSpan(
            text: text.substring(index, index + query.length),
            style: highlightStyle,
          ),
          TextSpan(text: text.substring(index + query.length)),
        ],
      ),
    );
  }
}
