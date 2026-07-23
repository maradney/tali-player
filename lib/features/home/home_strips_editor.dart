import 'package:flutter/material.dart';

import '../../data/models/account.dart';
import '../../data/models/category.dart';
import '../../data/models/home_strip.dart';
import '../../data/models/search_result.dart';
import '../../data/services/home_strips_service.dart';
import '../../data/sources/media_source.dart';
import '../../l10n/app_localizations.dart';
import '../common/api_error_helper.dart';
import '../common/category_label.dart';

/// The "Customize Home" bottom sheet: drag to reorder the dashboard's rails,
/// switch them on/off, remove category rails, and add new ones from the
/// catalog. Edits apply (and persist) immediately via [HomeStripsService].
class HomeStripsEditor extends StatelessWidget {
  final Account account;

  /// Content types with any catalog items — the add-category flow only offers
  /// these (matches the quick cards / hidden nav tabs).
  final Set<ContentType> availableTypes;

  const HomeStripsEditor({
    super.key,
    required this.account,
    required this.availableTypes,
  });

  /// The user-facing name of one strip.
  static String stripLabel(HomeStrip strip, AppLocalizations l) {
    switch (strip.type) {
      case HomeStripType.continueWatching:
        return l.continueWatching;
      case HomeStripType.watchlist:
        return l.watchlistTitle;
      case HomeStripType.recentlyAdded:
        return l.recentlyAddedTitle;
      case HomeStripType.downloads:
        return l.downloadsTitle;
      case HomeStripType.favorites:
        return l.favoritesTitle;
      case HomeStripType.category:
        return categoryDisplayName(
          Category(
            categoryId: strip.categoryId ?? '',
            categoryName: strip.categoryName ?? strip.categoryId ?? '',
          ),
          l,
        );
    }
  }

  Future<void> _addCategory(BuildContext context) async {
    final picked = await showDialog<
        ({ContentType type, Category category})>(
      context: context,
      builder: (_) => _CategoryPickerDialog(
        account: account,
        availableTypes: availableTypes,
      ),
    );
    if (picked == null) return;
    await HomeStripsService.instance.addCategory(
      type: picked.type,
      categoryId: picked.category.categoryId,
      categoryName: picked.category.categoryName,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return SafeArea(
      child: AnimatedBuilder(
        animation: HomeStripsService.instance,
        builder: (context, _) {
          final strips = HomeStripsService.instance.strips;
          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.7,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Row(
                    children: [
                      Text(
                        l.customizeHome,
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ReorderableListView.builder(
                    shrinkWrap: true,
                    buildDefaultDragHandles: false,
                    itemCount: strips.length,
                    // Unlike the deprecated onReorder, newIndex arrives
                    // already adjusted for the removed item.
                    onReorderItem: (oldIndex, newIndex) {
                      final next = List.of(strips);
                      next.insert(newIndex, next.removeAt(oldIndex));
                      HomeStripsService.instance.setStrips(next);
                    },
                    itemBuilder: (context, index) {
                      final strip = strips[index];
                      return ListTile(
                        key: ValueKey(strip.key),
                        leading: ReorderableDragStartListener(
                          index: index,
                          child: const Icon(Icons.drag_handle),
                        ),
                        title: Text(stripLabel(strip, l)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Category rails can be removed outright; built-in
                            // rails only toggle.
                            if (strip.type == HomeStripType.category)
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                tooltip: l.remove,
                                onPressed: () => HomeStripsService.instance
                                    .remove(strip.key),
                              ),
                            Switch(
                              value: strip.enabled,
                              onChanged: (_) => HomeStripsService.instance
                                  .toggle(strip.key),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.add),
                  title: Text(l.addCategoryRail),
                  onTap: () => _addCategory(context),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Two-step picker: content type (only when more than one is available),
/// then that type's categories from the account's source.
class _CategoryPickerDialog extends StatefulWidget {
  final Account account;
  final Set<ContentType> availableTypes;

  const _CategoryPickerDialog({
    required this.account,
    required this.availableTypes,
  });

  @override
  State<_CategoryPickerDialog> createState() => _CategoryPickerDialogState();
}

class _CategoryPickerDialogState extends State<_CategoryPickerDialog> {
  late ContentType _type = ContentType.values
      .firstWhere(widget.availableTypes.contains,
          orElse: () => ContentType.live);
  late Future<List<Category>> _categories = _load();

  Future<List<Category>> _load() {
    final source = MediaSource.forAccount(widget.account);
    switch (_type) {
      case ContentType.live:
        return source.getLiveCategories();
      case ContentType.movie:
        return source.getVodCategories();
      case ContentType.series:
        return source.getSeriesCategories();
    }
  }

  String _typeLabel(ContentType type, AppLocalizations l) {
    switch (type) {
      case ContentType.live:
        return l.tabLive;
      case ContentType.movie:
        return l.tabMovies;
      case ContentType.series:
        return l.tabSeries;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final types =
        ContentType.values.where(widget.availableTypes.contains).toList();
    return AlertDialog(
      title: Text(l.addCategoryRail),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (types.length > 1)
              SegmentedButton<ContentType>(
                segments: [
                  for (final t in types)
                    ButtonSegment(value: t, label: Text(_typeLabel(t, l))),
                ],
                selected: {_type},
                onSelectionChanged: (sel) => setState(() {
                  _type = sel.first;
                  _categories = _load();
                }),
              ),
            const SizedBox(height: 12),
            Flexible(
              child: SizedBox(
                height: 300,
                child: FutureBuilder<List<Category>>(
                  future: _categories,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          describeApiError(
                              snapshot.error!, widget.account, l),
                          textAlign: TextAlign.center,
                        ),
                      );
                    }
                    if (!snapshot.hasData) {
                      return const Center(
                          child: CircularProgressIndicator());
                    }
                    final categories = snapshot.data!;
                    if (categories.isEmpty) {
                      return Center(child: Text(l.noItemsInCategory));
                    }
                    return ListView.builder(
                      itemCount: categories.length,
                      itemBuilder: (context, index) {
                        final c = categories[index];
                        return ListTile(
                          title: Text(categoryDisplayName(c, l)),
                          onTap: () => Navigator.pop(
                              context, (type: _type, category: c)),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
      ],
    );
  }
}
