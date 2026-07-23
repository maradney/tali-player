import 'package:flutter/material.dart';

import '../../data/models/account.dart';
import '../../data/models/category.dart';
import '../../data/services/accounts_service.dart';
import '../../data/services/kids_filter_service.dart';
import '../../data/sources/media_source.dart';
import '../../l10n/app_localizations.dart';
import '../auth/login_screen.dart';
import '../common/category_label.dart';

/// The parent's curation surface for a kids profile: a master "restrict"
/// switch plus, per content type, a checklist of categories to allow. Operates
/// on one playlist at a time (a dropdown appears when the profile has more than
/// one), reading/writing [KidsFilterService] for that playlist's account.
///
/// Must be shown while the kids profile is active, so the active account's
/// categories and allowlist are the ones in scope.
class KidsContentScreen extends StatefulWidget {
  const KidsContentScreen({super.key});

  @override
  State<KidsContentScreen> createState() => _KidsContentScreenState();
}

class _KidsContentScreenState extends State<KidsContentScreen> {
  Account? _account;
  MediaSource? _source;
  Future<_Categories>? _categoriesFuture;

  @override
  void initState() {
    super.initState();
    _selectAccount(AccountsService.instance.activeAccount);
  }

  void _selectAccount(Account? account) {
    setState(() {
      _account = account;
      if (account == null) {
        _source = null;
        _categoriesFuture = null;
      } else {
        _source = MediaSource.forAccount(account);
        _categoriesFuture = _loadCategories(_source!);
      }
    });
    // Point the filter service at this playlist so the checkboxes and the
    // master switch reflect/mutate its stored allowlist.
    if (account != null) KidsFilterService.instance.loadFor(account);
  }

  Future<_Categories> _loadCategories(MediaSource source) async {
    // Fetch the three lists in parallel; a type with no categories just yields
    // an empty section (a channels-only M3U shows Live only).
    final results = await Future.wait([
      source.getLiveCategories().catchError((_) => <Category>[]),
      source.getVodCategories().catchError((_) => <Category>[]),
      source.getSeriesCategories().catchError((_) => <Category>[]),
    ]);
    return _Categories(live: results[0], movies: results[1], series: results[2]);
  }

  Future<void> _addPlaylist() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => LoginScreen(onAdded: () => Navigator.pop(context)),
      ),
    );
    // A playlist may have been added to this (active) profile — re-evaluate.
    if (mounted) _selectAccount(AccountsService.instance.activeAccount);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final accounts = AccountsService.instance.accounts;
    return Scaffold(
      appBar: AppBar(title: Text(l.kidsContentTitle)),
      body: _account == null
          ? _NoPlaylist(onAdd: _addPlaylist)
          : AnimatedBuilder(
              animation: KidsFilterService.instance,
              builder: (context, _) => ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.shield_outlined,
                            color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 12),
                        Expanded(child: Text(l.kidsRestrictSubtitle)),
                      ],
                    ),
                  ),
                  if (accounts.length > 1)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: DropdownButtonFormField<String>(
                        initialValue: _account!.key,
                        decoration:
                            InputDecoration(labelText: l.kidsSelectPlaylist),
                        items: [
                          for (final a in accounts)
                            DropdownMenuItem(
                                value: a.key, child: Text(a.name)),
                        ],
                        onChanged: (key) {
                          if (key == null) return;
                          _selectAccount(
                              accounts.firstWhere((a) => a.key == key));
                        },
                      ),
                    ),
                  const Divider(),
                  FutureBuilder<_Categories>(
                    future: _categoriesFuture,
                    builder: (context, snap) {
                      if (snap.connectionState != ConnectionState.done) {
                        return const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      final cats = snap.data;
                      if (cats == null || cats.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(l.kidsCategoriesEmpty,
                              textAlign: TextAlign.center),
                        );
                      }
                      return Column(
                        children: [
                          if (cats.live.isNotEmpty)
                            _CategorySection(
                                type: 'live',
                                title: l.navLiveTv,
                                categories: cats.live),
                          if (cats.movies.isNotEmpty)
                            _CategorySection(
                                type: 'movie',
                                title: l.navMovies,
                                categories: cats.movies),
                          if (cats.series.isNotEmpty)
                            _CategorySection(
                                type: 'series',
                                title: l.navSeries,
                                categories: cats.series),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
    );
  }
}

/// One collapsible content-type section with an allow-all/none header action
/// and a checkbox per category, bound live to [KidsFilterService].
class _CategorySection extends StatelessWidget {
  final String type;
  final String title;
  final List<Category> categories;

  const _CategorySection({
    required this.type,
    required this.title,
    required this.categories,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final svc = KidsFilterService.instance;
    final allowedCount =
        categories.where((c) => svc.isAllowed(type, c.categoryId)).length;
    return ExpansionTile(
      title: Text(title),
      subtitle: Text('$allowedCount / ${categories.length}'),
      childrenPadding: const EdgeInsets.only(bottom: 8),
      children: [
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(end: 12),
            child: Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () {
                    for (final c in categories) {
                      svc.setAllowed(type, c.categoryId, true);
                    }
                  },
                  child: Text(l.kidsAllowAll),
                ),
                TextButton(
                  onPressed: () {
                    for (final c in categories) {
                      svc.setAllowed(type, c.categoryId, false);
                    }
                  },
                  child: Text(l.kidsAllowNone),
                ),
              ],
            ),
          ),
        ),
        for (final c in categories)
          CheckboxListTile(
            dense: true,
            title: Text(categoryDisplayName(c, l)),
            value: svc.isAllowed(type, c.categoryId),
            onChanged: (v) => svc.setAllowed(type, c.categoryId, v ?? false),
          ),
      ],
    );
  }
}

class _NoPlaylist extends StatelessWidget {
  final VoidCallback onAdd;
  const _NoPlaylist({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.playlist_add,
                size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(l.kidsNoPlaylist, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: Text(l.addPlaylist),
            ),
          ],
        ),
      ),
    );
  }
}

class _Categories {
  final List<Category> live;
  final List<Category> movies;
  final List<Category> series;
  const _Categories(
      {required this.live, required this.movies, required this.series});
  bool get isEmpty => live.isEmpty && movies.isEmpty && series.isEmpty;
}
