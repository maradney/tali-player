import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/api/xtream_api_service.dart';
import '../../data/db/catalog_database.dart';
import '../../data/models/account.dart';
import '../../data/models/search_result.dart';
import '../../data/services/accounts_service.dart';
import '../../data/services/catalog_enrichment_service.dart';
import '../../data/services/catalog_sync_service.dart';
import '../../data/services/channel_preferences_service.dart';
import '../../data/services/download_service.dart';
import '../../data/services/favorites_service.dart';
import '../../data/services/home_strips_service.dart';
import '../../data/services/kids_filter_service.dart';
import '../../data/services/pin_lock_service.dart';
import '../../data/services/playback_service.dart';
import '../../data/services/watch_history_service.dart';
import '../../data/services/watchlist_service.dart';
import '../../l10n/app_localizations.dart';
import '../accounts/accounts_screen.dart';
import '../auth/login_screen.dart';
import '../browse/browse_screen.dart';
import '../common/disclaimer_dialog.dart';
import '../common/layout_breakpoints.dart';
import '../profiles/profile_picker_screen.dart';
import '../common/sync_status_toast.dart';
import '../favorites/favorites_screen.dart';
import '../history/watch_history_screen.dart';
import '../live_tv/live_tv_screen.dart';
import '../movies/movies_screen.dart';
import '../recent/recently_added_screen.dart';
import '../search/search_screen.dart';
import '../series/series_screen.dart';
import '../settings/settings_screen.dart';
import '../watchlist/watchlist_screen.dart';
import 'home_dashboard_screen.dart';

/// The three content-type nav destinations that get hidden when their catalog
/// is empty, mapped to the content type each browses. Their positions match
/// the `_destinations` list order (Home is 0).
const _typeDestinationIndex = <int, ContentType>{
  1: ContentType.live,
  2: ContentType.movie,
  3: ContentType.series,
};

/// Destinations that don't apply to M3U playlists and are hidden for them:
/// New/Recently-Added (M3U carries no added dates), Browse (needs enhanced-
/// search enrichment, which is Xtream-only), Watchlist, History, and Search.
/// M3U keeps just Home, Live, Movies, Series, and Favorites.
const _m3uHiddenDestinationIndices = <int>{4, 5, 7, 8, 9};

/// The real `_destinations` indices to show in the nav bar/rail. The
/// Live/Movies/Series destinations are hidden when their catalog is empty; for
/// M3U the [_m3uHiddenDestinationIndices] are dropped too. Everything else
/// always shows. Pure so the hide logic is unit-testable.
List<int> visibleDestinationIndices(
  int total,
  Set<ContentType> available, {
  bool isM3u = false,
}) =>
    [
      for (var i = 0; i < total; i++)
        if ((!_typeDestinationIndex.containsKey(i) ||
                available.contains(_typeDestinationIndex[i])) &&
            !(isM3u && _m3uHiddenDestinationIndices.contains(i)))
          i,
    ];

/// Most destinations a phone's bottom bar shows, the last of which is "More"
/// when there are others to hold. Material specifies 3-5 for a NavigationBar;
/// the app has ten, which on a ~410dp phone wrapped and clipped every label
/// ("Movie s", "Favorit es", "Histor y", and Search cut off by the edge).
const kMaxBottomBarDestinations = 5;

/// Splits [visible] into the destinations the bottom bar shows directly and
/// those that go behind "More".
///
/// Everything fits when there are few enough - which is the M3U case, where
/// half the destinations are hidden anyway - and no "More" entry is added.
/// Otherwise the bar keeps the first [max] - 1 in destination order, so the
/// content types people came for (Home, Live TV, Movies, Series) stay one tap
/// away and the long tail moves into the sheet.
///
/// Pure so the arithmetic is testable without a widget tree.
({List<int> bar, List<int> overflow}) splitDestinationsForBar(
  List<int> visible, {
  int max = kMaxBottomBarDestinations,
}) {
  if (visible.length <= max) return (bar: visible, overflow: const []);
  return (
    bar: visible.take(max - 1).toList(),
    overflow: visible.skip(max - 1).toList(),
  );
}

/// Index of the Search destination in `_destinations`.
const kSearchDestination = 9;

/// The order the "More" sheet lists [overflow] in, with Search pinned first.
///
/// `_destinations` order has to put the content types first, because that same
/// order decides what the bottom bar keeps — which left Search last of ten, and
/// so last in this sheet too: the thing people open the sheet for, behind the
/// most scanning. Pinning it here reorders the sheet without disturbing the bar.
///
/// Pure, like [splitDestinationsForBar], so it is testable without a tree.
List<int> moreSheetOrder(List<int> overflow) => [
      if (overflow.contains(kSearchDestination)) kSearchDestination,
      ...overflow.where((i) => i != kSearchDestination),
    ];

/// The destination to actually select given what's visible: [selected] itself
/// when it survived the filtering, otherwise the first visible destination
/// (Home — index 0 is never hidden). Guards against a stale selection after
/// an account switch hides the tab the user was on (e.g. Search → M3U), which
/// would otherwise leave the IndexedStack showing a hidden screen while the
/// nav highlighted a different one. Pure so it's unit-testable.
int effectiveSelectedIndex(int selected, List<int> visible) =>
    visible.contains(selected) ? selected : visible.first;

/// Hosts the main app UI for whichever account is currently active in
/// AccountsService. Reads the account reactively (rather than taking one
/// via constructor) so switching playlists updates this screen in place
/// without needing to tear down and recreate it.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selectedIndex = 0;
  String? _lastAccountKey;

  // Which tabs have been visited. A tab's screen is only built on its first
  // visit (so opening the app doesn't fire all six tabs' network fetches at
  // once), but afterwards it stays alive inside the IndexedStack - switching
  // tabs no longer disposes/recreates screens, which used to re-fetch
  // categories and items from the panel on every single tab switch (and was
  // a meaningful contributor to tripping the panel's 429 rate limit).
  Set<int> _visitedTabs = {0};

  static const _allContentTypes = {
    ContentType.live,
    ContentType.movie,
    ContentType.series,
  };

  // Which of Live/Movies/Series have catalog items. Only ever narrowed for M3U
  // playlists (an Xtream panel always exposes all three via its API, and its
  // background catalog index shouldn't hide a tab before it finishes). Updated
  // when the account changes and when a sync completes.
  Set<ContentType> _availableTypes = _allContentTypes;

  static final _destinations =
      <({IconData icon, String Function(AppLocalizations l) label})>[
    (icon: Icons.home, label: (l) => l.navHome),
    (icon: Icons.live_tv, label: (l) => l.navLiveTv),
    (icon: Icons.movie, label: (l) => l.navMovies),
    (icon: Icons.video_library, label: (l) => l.navSeries),
    (icon: Icons.fiber_new, label: (l) => l.navRecent),
    (icon: Icons.category, label: (l) => l.navBrowse),
    (icon: Icons.star, label: (l) => l.navFavorites),
    (icon: Icons.bookmark, label: (l) => l.navWatchlist),
    (icon: Icons.history, label: (l) => l.navHistory),
    (icon: Icons.search, label: (l) => l.navSearch),
  ];

  @override
  void initState() {
    super.initState();
    // Kick off the side effects for whichever account is active on first
    // build directly, without setState - the widget hasn't built yet, so
    // there's nothing to invalidate.
    final account = AccountsService.instance.activeAccount;
    if (account != null) {
      _lastAccountKey = account.key;
      unawaited(FavoritesService.instance.loadFor(account));
      unawaited(WatchlistService.instance.loadFor(account));
      unawaited(DownloadService.instance.loadFor(account));
      unawaited(PlaybackService.instance.loadFor(account));
      unawaited(WatchHistoryService.instance.loadFor(account));
      unawaited(PinLockService.instance.loadFor(account));
      unawaited(KidsFilterService.instance.loadFor(account));
      unawaited(ChannelPreferencesService.instance.loadFor(account));
      unawaited(HomeStripsService.instance.loadFor(account));
      _syncAndEnrich(account);
      unawaited(_refreshAvailableTypes(account));
    }
    AccountsService.instance.addListener(_onAccountsChanged);
    // A completed sync (or M3U refresh) may add/remove content types, so
    // recompute which type tabs to show whenever it fires.
    CatalogSyncService.instance.addListener(_onSyncChanged);
    if (account == null) _onAccountsChanged();
  }

  @override
  void dispose() {
    AccountsService.instance.removeListener(_onAccountsChanged);
    CatalogSyncService.instance.removeListener(_onSyncChanged);
    super.dispose();
  }

  void _onSyncChanged() {
    final account = AccountsService.instance.activeAccount;
    if (account != null) unawaited(_refreshAvailableTypes(account));
  }

  /// Recomputes [_availableTypes]. Xtream always shows all three type tabs;
  /// M3U hides the ones with no catalog items (a channels-only playlist shows
  /// Live only, etc.).
  Future<void> _refreshAvailableTypes(Account account) async {
    if (!account.isM3u) {
      if (_availableTypes.length != _allContentTypes.length) {
        setState(() => _availableTypes = _allContentTypes);
      }
      return;
    }
    final available = <ContentType>{};
    for (final type in _allContentTypes) {
      if (await CatalogDatabase.instance.countFor(account.key, type: type) > 0) {
        available.add(type);
      }
    }
    if (!mounted || account.key != _lastAccountKey) return;
    if (available.length != _availableTypes.length ||
        !available.containsAll(_availableTypes)) {
      setState(() => _availableTypes = available);
    }
  }

  void _onAccountsChanged() {
    final account = AccountsService.instance.activeAccount;
    if (account == null) {
      // Last account was removed - bail out to the login/add-playlist flow.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      });
      return;
    }
    if (account.key != _lastAccountKey) {
      _lastAccountKey = account.key;
      unawaited(FavoritesService.instance.loadFor(account));
      unawaited(WatchlistService.instance.loadFor(account));
      unawaited(DownloadService.instance.loadFor(account));
      unawaited(PlaybackService.instance.loadFor(account));
      unawaited(WatchHistoryService.instance.loadFor(account));
      unawaited(PinLockService.instance.loadFor(account));
      unawaited(KidsFilterService.instance.loadFor(account));
      unawaited(ChannelPreferencesService.instance.loadFor(account));
      unawaited(HomeStripsService.instance.loadFor(account));
      _syncAndEnrich(account);
      // A different account can expose different content types; assume all are
      // present until its catalog counts come back (avoids hiding tabs during
      // the switch), then narrow for M3U.
      _availableTypes = _allContentTypes;
      unawaited(_refreshAvailableTypes(account));
      // Forget which tabs were visited - the new account's screens should
      // load lazily on first visit too, not all at once right now.
      setState(() => _visitedTabs = {_selectedIndex});
    }
  }

  /// Refreshes the search index, then (if enhanced search is on) continues the
  /// per-item cast/director crawl. Chained so the enrichment picks up any rows
  /// this sync just added; both are fire-and-forget so neither blocks the UI.
  void _syncAndEnrich(Account account) {
    final api = XtreamApiService();
    unawaited(CatalogSyncService.instance.syncIfNeeded(account, api).then(
      (_) => CatalogEnrichmentService.instance.enrichIfEnabled(account, api),
    ));
  }

  List<Widget> _screensFor(Account account) => [
        HomeDashboardScreen(
          key: ValueKey('home_${account.key}'),
          account: account,
          availableTypes: _availableTypes,
          // Indices match the destinations list order below.
          onOpenLiveTv: () => _onTabSelected(1),
          onOpenMovies: () => _onTabSelected(2),
          onOpenSeries: () => _onTabSelected(3),
          onOpenRecentlyAdded: () => _onTabSelected(4),
          onOpenFavorites: () => _onTabSelected(6),
          onOpenWatchlist: () => _onTabSelected(7),
          onOpenSearch: () => _onTabSelected(kSearchDestination),
        ),
        LiveTvScreen(key: ValueKey('live_${account.key}'), account: account),
        MoviesScreen(key: ValueKey('movies_${account.key}'), account: account),
        SeriesScreen(key: ValueKey('series_${account.key}'), account: account),
        RecentlyAddedScreen(
            key: ValueKey('recent_${account.key}'), account: account),
        BrowseScreen(key: ValueKey('browse_${account.key}'), account: account),
        FavoritesScreen(
            key: ValueKey('favorites_${account.key}'), account: account),
        WatchlistScreen(
            key: ValueKey('watchlist_${account.key}'), account: account),
        WatchHistoryScreen(
            key: ValueKey('history_${account.key}'), account: account),
        SearchScreen(key: ValueKey('search_${account.key}'), account: account),
      ];

  void _openAccounts() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AccountsScreen()),
    );
  }

  void _openSettings(Account account) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SettingsScreen(account: account)),
    );
  }

  /// Opens the profile picker, clearing the shell — selecting a profile there
  /// swaps the whole app to that profile's isolated data.
  void _switchProfile() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const ProfilePickerScreen()),
      (route) => false,
    );
  }

  void _onTabSelected(int index) {
    setState(() {
      _selectedIndex = index;
      _visitedTabs.add(index);
    });
  }

  /// The phone bottom bar: the first few destinations, plus "More" holding the
  /// rest. "More" shows as selected while one of its destinations is open, so
  /// the bar never highlights nothing.
  Widget _buildBottomBar(
      AppLocalizations l, List<int> visible, int selectedIndex) {
    final split = splitDestinationsForBar(visible);
    final barPos = split.bar.indexOf(selectedIndex);
    final isOverflowSelected = barPos < 0;
    return NavigationBar(
      selectedIndex: isOverflowSelected ? split.bar.length : barPos,
      onDestinationSelected: (pos) {
        if (pos < split.bar.length) {
          _onTabSelected(split.bar[pos]);
        } else {
          _openMoreSheet(l, split.overflow, selectedIndex);
        }
      },
      destinations: [
        for (final i in split.bar)
          NavigationDestination(
            icon: Icon(_destinations[i].icon),
            label: _destinations[i].label(l),
          ),
        if (split.overflow.isNotEmpty)
          NavigationDestination(icon: const Icon(Icons.more_horiz), label: l.more),
      ],
    );
  }

  Future<void> _openMoreSheet(
      AppLocalizations l, List<int> overflow, int selectedIndex) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final i in moreSheetOrder(overflow))
              ListTile(
                leading: Icon(_destinations[i].icon),
                title: Text(_destinations[i].label(l)),
                selected: i == selectedIndex,
                onTap: () {
                  Navigator.pop(sheetContext);
                  _onTabSelected(i);
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final account = AccountsService.instance.activeAccount;
    if (account == null) {
      // Waiting on the post-frame redirect to LoginScreen above.
      return const Scaffold(body: SizedBox.shrink());
    }
    final screens = _screensFor(account);
    // Which destinations to show (empty Live/Movies/Series tabs are hidden for
    // M3U). The IndexedStack/screens list stays full and indexed by the real
    // destination index, so we map the nav bar's visible position <-> real
    // index rather than renumbering everything.
    final visible = visibleDestinationIndices(
        _destinations.length, _availableTypes,
        isM3u: account.isM3u);
    // A stale selection (its tab hidden by an account switch) falls back to
    // the first visible destination for BOTH the nav highlight and the body,
    // so they can never disagree.
    final selectedIndex = effectiveSelectedIndex(_selectedIndex, visible);
    final selectedPos = visible.indexOf(selectedIndex);
    // Visited screens stay mounted (hidden, not disposed) so switching back
    // to a tab is instant and doesn't re-fetch from the panel; unvisited
    // ones stay as empty placeholders until first opened.
    final body = IndexedStack(
      index: selectedIndex,
      children: [
        for (var i = 0; i < screens.length; i++)
          // The shown tab always builds, even when the selection just fell
          // back to Home (which may not be in _visitedTabs after an account
          // switch reset it) — otherwise the fallback would render a blank.
          _visitedTabs.contains(i) || i == selectedIndex
              ? screens[i]
              : const SizedBox.shrink(),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = isWideLayout(constraints.maxWidth);

        if (isWide) {
          return Scaffold(
            body: Stack(
              children: [
                Row(
                  children: [
                    // Scrollable so a short window (or many destinations)
                    // doesn't overflow the rail; still fills the height and
                    // pins the trailing actions to the bottom when tall.
                    SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints:
                            BoxConstraints(minHeight: constraints.maxHeight),
                        child: IntrinsicHeight(
                          child: NavigationRail(
                      selectedIndex: selectedPos,
                      onDestinationSelected: (pos) => _onTabSelected(visible[pos]),
                      labelType: NavigationRailLabelType.all,
                      leading: _AccountSwitcherButton(
                        account: account,
                        onTap: _openAccounts,
                      ),
                      trailing: Expanded(
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.switch_account_outlined),
                                  tooltip: l.switchProfile,
                                  onPressed: _switchProfile,
                                ),
                                IconButton(
                                  icon: const Icon(Icons.settings_outlined),
                                  tooltip: l.settingsTitle,
                                  onPressed: () => _openSettings(account),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.info_outline),
                                  tooltip: l.settingsAboutThisApp,
                                  onPressed: () => showDisclaimerDialog(context),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      destinations: [
                        for (final i in visible)
                          NavigationRailDestination(
                            icon: Icon(_destinations[i].icon),
                            label: Text(_destinations[i].label(l)),
                          ),
                      ],
                          ),
                        ),
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: body),
                  ],
                ),
                const SyncStatusToast(),
              ],
            ),
          );
        }

        return Scaffold(
          appBar: ShellAppBar(
            account: account,
            onOpenAccounts: _openAccounts,
            onSwitchProfile: _switchProfile,
            onOpenSettings: () => _openSettings(account),
            onOpenAbout: () => showDisclaimerDialog(context),
          ),
          // Narrow: the sync card takes its own strip above the nav bar rather
          // than floating, which on a phone covered the bottom row of posters.
          body: Column(
            children: [
              Expanded(child: body),
              const SyncStatusBanner(),
            ],
          ),
          bottomNavigationBar: _buildBottomBar(l, visible, selectedIndex),
        );
      },
    );
  }
}

/// The narrow-layout shell bar: which playlist is active, plus profile,
/// settings and about. Only exists below [kWideLayoutBreakpoint] — the wide
/// layout puts all of this in the NavigationRail instead.
///
/// It sits *above* each tab screen's own app bar, so nothing ever scrolls
/// under this one; the bar directly over the content is the one that should
/// pick up the scrolled-under tint. Reacting to scroll here was also actively
/// broken: a Scaffold wraps its whole subtree (this bar included) in a
/// ScrollNotificationObserver, and observers pass notifications on upward, so
/// this bar received every tab's scrolling no matter how many observers sat
/// between. Switching tabs emits no scroll notification, so it kept whichever
/// tint the last tab left behind until you scrolled the new tab down and back
/// up. Ignoring scroll outright is both the correct semantics and the fix.
class ShellAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Account account;
  final VoidCallback onOpenAccounts;
  final VoidCallback onSwitchProfile;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenAbout;

  const ShellAppBar({
    super.key,
    required this.account,
    required this.onOpenAccounts,
    required this.onSwitchProfile,
    required this.onOpenSettings,
    required this.onOpenAbout,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AppBar(
      notificationPredicate: (_) => false,
      title: _AccountSwitcherButton(account: account, onTap: onOpenAccounts),
      actions: [
        IconButton(
          icon: const Icon(Icons.switch_account_outlined),
          tooltip: l.switchProfile,
          onPressed: onSwitchProfile,
        ),
        IconButton(
          icon: const Icon(Icons.settings_outlined),
          tooltip: l.settingsTitle,
          onPressed: onOpenSettings,
        ),
        IconButton(
          icon: const Icon(Icons.info_outline),
          tooltip: l.settingsAboutThisApp,
          onPressed: onOpenAbout,
        ),
      ],
    );
  }
}

/// Small button showing the active account's name; tapping it opens the
/// playlist switcher/manager.
class _AccountSwitcherButton extends StatelessWidget {
  final Account account;
  final VoidCallback onTap;

  const _AccountSwitcherButton({
    required this.account,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.playlist_play),
            const SizedBox(height: 4),
            // Capped so a long name (e.g. an M3U playlist URL) can't stretch the
            // whole nav rail — it ellipsizes instead.
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 96),
              child: Text(
                account.name,
                style: Theme.of(context).textTheme.labelSmall,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}