import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/db/catalog_database.dart';
import '../../data/models/account.dart';
import '../../data/models/catalog_row.dart';
import '../../data/services/catalog_enrichment_service.dart';
import '../../data/services/kids_filter_service.dart';
import '../../data/services/pin_lock_service.dart';
import '../../data/services/settings_service.dart';
import '../../l10n/app_localizations.dart';
import '../common/downloads_button.dart';
import '../settings/settings_screen.dart';
import 'genre_browse_screen.dart';

/// Global "Browse by genre" landing — a flat, cross-category view of every
/// genre found across the catalog, powered entirely by the offline enrichment
/// index (no API calls). Tapping a genre drills into [GenreBrowseScreen].
///
/// The genre data only exists once Enhanced search has run (it captures each
/// title's genre), so when that's off the screen explains the dependency and
/// links to Settings; while the crawl is still running it shows whatever
/// genres exist so far, with a hint that more will appear.
class BrowseScreen extends StatefulWidget {
  final Account account;
  const BrowseScreen({super.key, required this.account});

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

/// Which one-line banner sits above the genre grid, if any.
enum BrowseBanner {
  /// Nothing to say — the index is complete, or nothing more is coming.
  none,

  /// The crawl is running (or can still find more with the setting on): more
  /// genres will appear on their own.
  indexing,

  /// The setting is off but there are still un-enriched titles — the genres
  /// shown are all we have; nudge the user that turning it on finds more.
  enableForMore,
}

/// Picks the banner from the enrichment state. There are still un-enriched
/// titles (`hasMore`) when the crawl hasn't covered everything. If enhanced
/// search is on (or actively running), those will fill in on their own →
/// [BrowseBanner.indexing]. If it's off, they won't — so nudge the user that
/// turning it on would find more ([BrowseBanner.enableForMore]). When
/// everything is already indexed, [BrowseBanner.none]. Pure + testable.
BrowseBanner computeBrowseBanner({
  required bool enhancedSearchOn,
  required bool running,
  required ({int enriched, int total})? progress,
}) {
  final hasMore = progress != null && progress.enriched < progress.total;
  if (enhancedSearchOn || running) {
    return (running || hasMore) ? BrowseBanner.indexing : BrowseBanner.none;
  }
  return hasMore ? BrowseBanner.enableForMore : BrowseBanner.none;
}

class _BrowseScreenState extends State<BrowseScreen> {
  late final String _accountKey = CatalogRow.accountKeyFor(widget.account);

  bool _loading = true;
  List<({String genre, int count})> _facets = [];

  /// Enriched vs total titles, read from the DB so the "more available" nudge
  /// is correct even across app restarts (in-memory crawl progress may be null
  /// when nothing has run this session).
  ({int enriched, int total})? _progress;

  /// Coalesces the flurry of change notifications during a crawl (the
  /// enrichment service notifies after *every* item) into at most one reload
  /// every couple of seconds, instead of a full genre re-scan per item.
  Timer? _reloadDebounce;

  @override
  void initState() {
    super.initState();
    // The crawl fills in genres over time, the settings flag can be toggled,
    // and locking/unlocking a category changes which genres are visible —
    // refresh the facets (debounced) when any of these change.
    CatalogEnrichmentService.instance.addListener(_onDataChanged);
    SettingsService.instance.addListener(_onDataChanged);
    PinLockService.instance.addListener(_onDataChanged);
    _load();
  }

  @override
  void dispose() {
    _reloadDebounce?.cancel();
    CatalogEnrichmentService.instance.removeListener(_onDataChanged);
    SettingsService.instance.removeListener(_onDataChanged);
    PinLockService.instance.removeListener(_onDataChanged);
    super.dispose();
  }

  void _onDataChanged() {
    _reloadDebounce?.cancel();
    _reloadDebounce = Timer(const Duration(seconds: 2), () {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    final db = CatalogDatabase.instance;
    final lockedCategories = PinLockService.instance.lockedCategoryKeys;
    final facets = await db.genreFacets(
      _accountKey,
      lockedCategoryKeys: lockedCategories,
      allowedCategoryKeys: KidsFilterService.instance.allowedCategoryKeysOrNull,
    );
    final progress = await db.enrichmentProgress(_accountKey);
    if (!mounted) return;
    setState(() {
      _facets = facets;
      _progress = progress;
      _loading = false;
    });
  }

  void _openGenre(String genre) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            GenreBrowseScreen(account: widget.account, genre: genre),
      ),
    );
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsScreen(account: widget.account),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.browseTitle),
        actions: [DownloadsButton(account: widget.account)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _facets.isEmpty
              ? _EmptyState(
                  enhancedSearchOn:
                      SettingsService.instance.enhancedSearchEnabled,
                  onOpenSettings: _openSettings,
                )
              : _GenreGrid(
                  facets: _facets,
                  onTap: _openGenre,
                  banner: _banner,
                  onOpenSettings: _openSettings,
                ),
    );
  }

  /// Which banner to show above the grid — see [computeBrowseBanner].
  BrowseBanner get _banner => computeBrowseBanner(
        enhancedSearchOn: SettingsService.instance.enhancedSearchEnabled,
        running: CatalogEnrichmentService.instance.isEnriching(widget.account),
        progress: _progress,
      );
}

/// Shown when there are no genres yet: either Enhanced search is off (explain
/// and offer to open Settings) or it's on but the crawl hasn't reached any
/// genre data yet (reassure it's coming).
class _EmptyState extends StatelessWidget {
  final bool enhancedSearchOn;
  final VoidCallback onOpenSettings;

  const _EmptyState({
    required this.enhancedSearchOn,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.category_outlined,
                  size: 56, color: Theme.of(context).disabledColor),
              const SizedBox(height: 16),
              Text(
                enhancedSearchOn
                    ? l.browseIndexingTitle
                    : l.browseNeedsIndexTitle,
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                enhancedSearchOn ? l.browseIndexingBody : l.browseNeedsIndexBody,
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              if (!enhancedSearchOn) ...[
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: onOpenSettings,
                  icon: const Icon(Icons.settings_outlined),
                  label: Text(l.browseOpenSettings),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _GenreGrid extends StatelessWidget {
  final List<({String genre, int count})> facets;
  final void Function(String genre) onTap;
  final BrowseBanner banner;
  final VoidCallback onOpenSettings;

  const _GenreGrid({
    required this.facets,
    required this.onTap,
    required this.banner,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Column(
      children: [
        if (banner != BrowseBanner.none)
          _BannerBar(
            icon: banner == BrowseBanner.indexing
                ? Icons.hourglass_top
                : Icons.info_outline,
            text: banner == BrowseBanner.indexing
                ? l.browseIndexingHint
                : l.browseEnableForMore,
            // Only the "off" nudge is actionable — offer to open Settings.
            action: banner == BrowseBanner.enableForMore
                ? TextButton(
                    onPressed: onOpenSettings,
                    child: Text(l.browseOpenSettings),
                  )
                : null,
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              const ideal = 220.0;
              const padding = 12.0;
              final available = constraints.maxWidth - padding * 2;
              final cols = (available / ideal).floor().clamp(1, 100);
              return GridView.builder(
                padding: const EdgeInsets.all(padding),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  mainAxisExtent: 72,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: facets.length,
                itemBuilder: (context, index) {
                  final f = facets[index];
                  return _GenreCard(
                    genre: f.genre,
                    subtitle: l.genreTitleCount(f.count),
                    onTap: () => onTap(f.genre),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/// One-line info strip above the genre grid, optionally with a trailing action.
class _BannerBar extends StatelessWidget {
  final IconData icon;
  final String text;
  final Widget? action;

  const _BannerBar({required this.icon, required this.text, this.action});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: EdgeInsets.only(
          left: 16, right: action != null ? 8 : 16, top: 10, bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodySmall),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}

class _GenreCard extends StatelessWidget {
  final String genre;
  final String subtitle;
  final VoidCallback onTap;

  const _GenreCard({
    required this.genre,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.local_movies_outlined,
                  color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      genre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
