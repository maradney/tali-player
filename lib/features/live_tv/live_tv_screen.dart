import 'package:flutter/material.dart';

import '../../data/models/account.dart';
import '../../data/models/category.dart';
import '../../data/models/channel.dart';
import '../../data/models/epg_program.dart';
import '../../data/models/favorite_item.dart';
import '../../data/services/channel_preferences_service.dart';
import '../../data/services/favorites_service.dart';
import '../../data/services/kids_filter_service.dart';
import '../../data/services/pin_lock_service.dart';
import '../../data/services/watch_history_service.dart';
import '../../data/sources/media_source.dart';
import '../../l10n/app_localizations.dart';
import '../common/api_error_helper.dart';
import '../common/browse_states.dart';
import '../common/cached_poster_image.dart';
import '../common/category_label.dart';
import '../common/category_rail.dart';
import '../common/downloads_button.dart';
import '../common/pin_dialogs.dart';
import '../common/quick_filter_field.dart';
import '../player/channel_player_screen.dart';
import 'epg_grid_screen.dart';

class LiveTvScreen extends StatefulWidget {
  final Account account;

  const LiveTvScreen({super.key, required this.account});

  @override
  State<LiveTvScreen> createState() => _LiveTvScreenState();
}

class _LiveTvScreenState extends State<LiveTvScreen> {
  late final _source = MediaSource.forAccount(widget.account);

  bool _loadingCategories = true;
  bool _loadingChannels = false;
  String? _error;

  List<Category> _categories = [];
  List<Channel> _channels = [];
  Category? _selectedCategory;

  // Cache the EPG *Future* (not the completed list) per channel: a rebuild
  // while a fetch is still in flight reuses the in-flight Future instead of
  // firing a duplicate request, and FutureBuilder keeps a stable Future
  // identity across rebuilds so it doesn't flash its loading state every
  // time a favorite star or lock icon changes.
  final Map<String, Future<List<EpgProgram>>> _epgCache = {};

  final _categoryFilterController = TextEditingController();
  final _filterController = TextEditingController();

  // Temporary view toggle (not persisted): reveals hidden channels so they
  // can be un-hidden, rather than being permanently invisible.
  bool _showHidden = false;

  List<Category> get _filteredCategories {
    final q = _categoryFilterController.text.trim().toLowerCase();
    if (q.isEmpty) return _categories;
    return _categories
        .where((c) => c.categoryName.toLowerCase().contains(q))
        .toList();
  }

  List<Channel> get _filteredChannels {
    // Apply the account's hide + sort preferences first, then the on-screen
    // name filter.
    var list = ChannelPreferencesService.instance
        .apply(_channels, includeHidden: _showHidden);
    final q = _filterController.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((c) => c.name.toLowerCase().contains(q)).toList();
    }
    return list;
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
      final rawCategories = await _source.getLiveCategories();
      if (!mounted) return;
      // Kids allowlist: disallowed categories are removed outright, so the
      // resume/first-unlocked logic below only ever considers visible ones.
      final categories = rawCategories
          .where((c) =>
              !KidsFilterService.instance.isCategoryHidden('live', c.categoryId))
          .toList();
      setState(() {
        _categories = categories;
        _loadingCategories = false;
      });
      if (categories.isNotEmpty) {
        // "Resume": land back in the category of the last channel watched
        // (persisted across restarts via watch history), as long as it still
        // exists and isn't locked. Otherwise fall back to the first unlocked
        // category rather than whatever's literally first - avoids surfacing a
        // locked category's channels (or popping a PIN dialog unprompted) just
        // from opening this tab.
        final resumeCategoryId =
            WatchHistoryService.instance.lastLiveEntry?.categoryId;
        Category? resumeCategory;
        if (resumeCategoryId != null) {
          for (final c in categories) {
            if (c.categoryId == resumeCategoryId &&
                !PinLockService.instance.isCategoryLocked('live', c.categoryId)) {
              resumeCategory = c;
              break;
            }
          }
        }
        final firstUnlocked = categories.firstWhere(
          (c) => !PinLockService.instance.isCategoryLocked('live', c.categoryId),
          orElse: () => categories.first,
        );
        final target = resumeCategory ?? firstUnlocked;
        if (PinLockService.instance.isCategoryLocked('live', target.categoryId)) {
          // Every category is locked - just select it without fetching;
          // the channel pane shows a locked placeholder until unlocked.
          setState(() => _selectedCategory = target);
        } else {
          _selectCategory(target);
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

  /// CategoryRail's onSelect - gates locked categories behind a PIN prompt
  /// before actually fetching/switching. [_selectCategory] itself stays
  /// unguarded since it's also used for the initial auto-selection.
  Future<void> _onCategoryTap(Category category) async {
    if (PinLockService.instance.isCategoryLocked('live', category.categoryId)) {
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
      _loadingChannels = true;
      _channels = [];
      _error = null;
    });
    try {
      final channels =
          await _source.getLiveStreams(category.categoryId);
      if (!mounted) return;
      setState(() {
        _channels = channels;
        _loadingChannels = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = describeApiError(e, widget.account, AppLocalizations.of(context)!);
        _loadingChannels = false;
      });
    }
  }

  Future<List<EpgProgram>> _epgFor(String streamId) {
    final cached = _epgCache[streamId];
    if (cached != null) return cached;
    final future = _source.getShortEpg(streamId);
    _epgCache[streamId] = future;
    // Don't cache a failed fetch forever - drop it so a later rebuild can
    // retry instead of showing "No guide data" until the screen is rebuilt.
    future.catchError((Object _) {
      _epgCache.remove(streamId);
      return <EpgProgram>[];
    });
    return future;
  }

  FavoriteItem _favoriteFor(Channel channel) => FavoriteItem(
        type: 'live',
        id: channel.streamId,
        name: channel.name,
        imageUrl: channel.logoUrl,
        categoryId: channel.categoryId,
      );

  Future<void> _playChannel(Channel channel) async {
    if (PinLockService.instance.isItemLocked('live', channel.streamId)) {
      final ok = await requirePin(context,
          title: AppLocalizations.of(context)!.enterPinToWatch(channel.name));
      if (!ok) return;
    }
    if (!mounted) return;
    final url = _source.liveUrl(channel);
    // Hand the player the list the user is browsing so it can zap prev/next
    // in place. If the channel isn't in the current list (e.g. a resume of a
    // channel from another category), fall back to a single-item list.
    final index = _filteredChannels.indexOf(channel);
    final zapList = index >= 0 ? _filteredChannels : [channel];
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChannelPlayerScreen(
          title: channel.name,
          streamUrl: url,
          httpHeaders:
              iptvStreamHeaders(channel, isM3u: widget.account.isM3u),
          epgFuture: _epgFor(channel.streamId),
          favoriteItem: _favoriteFor(channel),
          channels: zapList,
          channelIndex: index >= 0 ? index : 0,
          account: widget.account,
        ),
      ),
    );
  }

  /// Plays the last-watched live channel again. Prefers the real Channel from
  /// the loaded list (accurate metadata + zapping within its category); if
  /// that category isn't loaded, reconstructs enough to play it standalone.
  Future<void> _resumeLastChannel() async {
    final last = WatchHistoryService.instance.lastLiveEntry;
    if (last == null) return;
    final inList = _channels.where((c) => c.streamId == last.id);
    // resolveChannel restores an M3U channel's playable URL/headers when the
    // history entry has to be reconstructed from its snapshot.
    final channel = inList.isNotEmpty
        ? inList.first
        : await _source.resolveChannel(Channel(
            streamId: last.id,
            name: last.name,
            categoryId: last.categoryId ?? '',
            logoUrl: last.imageUrl,
          ));
    await _playChannel(channel);
  }

  Future<void> _toggleHide(Channel channel) async {
    final prefs = ChannelPreferencesService.instance;
    final nowHidden = !prefs.isHidden(channel.streamId);
    await prefs.setHidden(channel.streamId, nowHidden);
    if (!mounted || !nowHidden) return;
    final l = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(l.hiddenChannel(channel.name)),
        // A close button matters on desktop: the auto-dismiss timer pauses
        // while the pointer hovers the snackbar (which it often is, right
        // after clicking the ⋮ menu), so it can otherwise sit there forever.
        showCloseIcon: true,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: l.undo,
          onPressed: () => prefs.setHidden(channel.streamId, false),
        ),
      ),
    );
  }

  void _openGrid() {
    if (_selectedCategory == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EpgGridScreen(
          account: widget.account,
          channels: _filteredChannels,
          categoryName: categoryDisplayName(
              _selectedCategory!, AppLocalizations.of(context)!),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final lastLive = WatchHistoryService.instance.lastLiveEntry;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.liveTvTitle),
        actions: [
          if (lastLive != null)
            IconButton(
              icon: const Icon(Icons.replay),
              tooltip: l.resumeChannel(lastLive.name),
              onPressed: _resumeLastChannel,
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort),
            tooltip: l.sortAndHidden,
            onSelected: (value) {
              final prefs = ChannelPreferencesService.instance;
              switch (value) {
                case 'sort:default':
                  prefs.setSortOrder(ChannelSort.providerDefault);
                case 'sort:asc':
                  prefs.setSortOrder(ChannelSort.nameAsc);
                case 'sort:desc':
                  prefs.setSortOrder(ChannelSort.nameDesc);
                case 'toggleHidden':
                  setState(() => _showHidden = !_showHidden);
              }
            },
            itemBuilder: (context) {
              final sort = ChannelPreferencesService.instance.sortOrder;
              final hiddenCount = ChannelPreferencesService.instance.hiddenCount;
              return [
                CheckedPopupMenuItem(
                  value: 'sort:default',
                  checked: sort == ChannelSort.providerDefault,
                  child: Text(l.sortDefault),
                ),
                CheckedPopupMenuItem(
                  value: 'sort:asc',
                  checked: sort == ChannelSort.nameAsc,
                  child: Text(l.sortNameAsc),
                ),
                CheckedPopupMenuItem(
                  value: 'sort:desc',
                  checked: sort == ChannelSort.nameDesc,
                  child: Text(l.sortNameDesc),
                ),
                const PopupMenuDivider(),
                CheckedPopupMenuItem(
                  value: 'toggleHidden',
                  checked: _showHidden,
                  child: Text('${l.showHiddenChannels}'
                      '${hiddenCount > 0 ? ' ($hiddenCount)' : ''}'),
                ),
              ];
            },
          ),
          IconButton(
            icon: const Icon(Icons.grid_view),
            tooltip: l.tvGuideGrid,
            onPressed: _selectedCategory == null ? null : _openGrid,
          ),
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
                            hintText: l.filterChannels,
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
                                  .isCategoryLocked('live', c.categoryId),
                              onLongPress: (c) => toggleCategoryLockPrompt(
                                context,
                                type: 'live',
                                categoryId: c.categoryId,
                                name: c.categoryName,
                              ),
                            ),
                          ),
                          const VerticalDivider(width: 1),
                          Expanded(
                            child: _loadingChannels
                                ? const Center(child: CircularProgressIndicator())
                                : _selectedCategory != null &&
                                        _channels.isEmpty &&
                                        PinLockService.instance.isCategoryLocked(
                                            'live', _selectedCategory!.categoryId)
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
                                    : AnimatedBuilder(
                                        // Rebuilds (and re-evaluates the empty
                                        // state) when favorites, locks, or the
                                        // hide/sort prefs change.
                                        animation: Listenable.merge([
                                          FavoritesService.instance,
                                          PinLockService.instance,
                                          ChannelPreferencesService.instance,
                                        ]),
                                        builder: (context, _) {
                                          final channels = _filteredChannels;
                                          if (channels.isEmpty) {
                                            return Center(
                                                child:
                                                    Text(l.noMatchingChannels));
                                          }
                                          return ListView.separated(
                                            itemCount: channels.length,
                                            separatorBuilder: (_, __) =>
                                                const Divider(height: 1),
                                            itemBuilder: (context, index) {
                                              final channel = channels[index];
                                              final prefs =
                                                  ChannelPreferencesService
                                                      .instance;
                                              return _ChannelTile(
                                                channel: channel,
                                                epgFuture:
                                                    _epgFor(channel.streamId),
                                                onTap: () =>
                                                    _playChannel(channel),
                                                isFavorite: FavoritesService
                                                    .instance
                                                    .isFavorite('live',
                                                        channel.streamId),
                                                onToggleFavorite: () =>
                                                    FavoritesService.instance
                                                        .toggle(_favoriteFor(
                                                            channel)),
                                                isLocked: PinLockService.instance
                                                    .isItemLocked('live',
                                                        channel.streamId),
                                                isHidden: prefs
                                                    .isHidden(channel.streamId),
                                                onToggleLock: () =>
                                                    toggleItemLockPrompt(
                                                  context,
                                                  type: 'live',
                                                  id: channel.streamId,
                                                  name: channel.name,
                                                ),
                                                onToggleHide: () =>
                                                    _toggleHide(channel),
                                              );
                                            },
                                          );
                                        },
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

/// A single channel row: logo, name, and a "Now" strip with a progress bar
/// showing how far through the current program we are.
class _ChannelTile extends StatelessWidget {
  final Channel channel;
  final Future<List<EpgProgram>> epgFuture;
  final VoidCallback onTap;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;
  final bool isLocked;
  final bool isHidden;
  final VoidCallback onToggleLock;
  final VoidCallback onToggleHide;

  const _ChannelTile({
    required this.channel,
    required this.epgFuture,
    required this.onTap,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.isLocked,
    required this.isHidden,
    required this.onToggleLock,
    required this.onToggleHide,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final tile = ListTile(
      leading: SizedBox(
        width: 48,
        height: 48,
        child: channel.logoUrl != null
            ? CachedPosterImage(
                imageUrl: channel.logoUrl!,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(Icons.tv, size: 32),
              )
            : const Icon(Icons.tv, size: 32),
      ),
      title: Text(channel.name),
      subtitle: FutureBuilder<List<EpgProgram>>(
        future: epgFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SizedBox(
              height: 4,
              child: LinearProgressIndicator(minHeight: 2),
            );
          }
          final programs = snapshot.data ?? [];
          if (programs.isEmpty) {
            return Text(l.noGuideData, style: const TextStyle(fontSize: 12));
          }
          final now = programs.first;
          return Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.nowProgram(now.title),
                  style: const TextStyle(fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: now.progress,
                    minHeight: 3,
                  ),
                ),
                if (programs.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      l.nextProgram(programs[1].title),
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
      isThreeLine: true,
      onTap: onTap,
      onLongPress: onToggleLock,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isHidden)
            Icon(Icons.visibility_off,
                size: 18, color: Theme.of(context).disabledColor),
          if (isLocked)
            Icon(Icons.lock, size: 18, color: Theme.of(context).disabledColor),
          IconButton(
            icon: Icon(
              isFavorite ? Icons.star : Icons.star_border,
              color: isFavorite ? Colors.amber : null,
            ),
            onPressed: onToggleFavorite,
          ),
          PopupMenuButton<String>(
            tooltip: l.more,
            onSelected: (value) {
              if (value == 'hide') onToggleHide();
              if (value == 'lock') onToggleLock();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'hide',
                child: Text(isHidden ? l.unhideChannel : l.hideChannel),
              ),
              PopupMenuItem(
                value: 'lock',
                child: Text(isLocked ? l.unlock : l.lock),
              ),
            ],
          ),
        ],
      ),
    );
    // A shown hidden channel (via "Show hidden channels") is dimmed so it's
    // clearly not part of the normal list.
    return isHidden ? Opacity(opacity: 0.5, child: tile) : tile;
  }
}

