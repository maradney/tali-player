import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'browse_sort.dart';

/// App-bar action for the browse grids/lists: pick how the current items are
/// ordered and, where the data supports it, a minimum rating.
///
/// A pure controlled widget — the state lives in the host screen and is
/// session-only, like the quick filter (it isn't persisted). It's configurable
/// per screen because the available data differs: Movies/Series offer every
/// sort plus a rating filter, Favorites drop "recently added" (no timestamp),
/// and History has no rating at all (so no rating sort/filter). The icon fills
/// in when any non-default sort or filter is active, hinting the list is
/// narrowed.
class SortFilterButton extends StatelessWidget {
  final BrowseSort sort;
  final double minRating;
  final ValueChanged<BrowseSort> onSortChanged;

  /// Which sort options to show, in menu order. The first entry is treated as
  /// the screen's natural default for the "active" indicator.
  final List<BrowseSort> sorts;

  /// When null, the rating filter section is hidden (e.g. History, which
  /// stores no rating). When set, [minRating] drives the checked threshold.
  final ValueChanged<double>? onMinRatingChanged;

  /// Overrides the label for [BrowseSort.providerDefault] — e.g. "Recently
  /// watched" on History, where the natural order is chronological rather than
  /// a provider order.
  final String? defaultSortLabel;

  const SortFilterButton({
    super.key,
    required this.sort,
    required this.onSortChanged,
    this.minRating = 0,
    this.sorts = BrowseSort.values,
    this.onMinRatingChanged,
    this.defaultSortLabel,
  });

  /// Coarse rating thresholds; 0 means "any" (no rating filter).
  static const _ratingThresholds = [0.0, 6.0, 7.0, 8.0, 9.0];

  bool get _active {
    final naturalDefault = sorts.isEmpty ? BrowseSort.providerDefault : sorts.first;
    return sort != naturalDefault || minRating > 0;
  }

  String _sortLabel(BrowseSort sort, AppLocalizations l) => switch (sort) {
        BrowseSort.providerDefault =>
          defaultSortLabel ?? l.sortProviderDefault,
        BrowseSort.nameAsc => l.sortNameAsc,
        BrowseSort.nameDesc => l.sortNameDesc,
        BrowseSort.ratingDesc => l.sortRatingHigh,
        BrowseSort.recentlyAdded => l.sortRecentlyAdded,
      };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final labelStyle = Theme.of(context).textTheme.labelSmall;
    final onRating = onMinRatingChanged;
    return PopupMenuButton<_SortFilterChoice>(
      tooltip: l.sortAndFilter,
      icon: Icon(_active ? Icons.filter_list : Icons.sort),
      onSelected: (choice) => choice.apply(this),
      itemBuilder: (context) => [
        PopupMenuItem(enabled: false, child: Text(l.sortBy, style: labelStyle)),
        for (final s in sorts)
          CheckedPopupMenuItem(
            value: _SortChoice(s),
            checked: s == sort,
            child: Text(_sortLabel(s, l)),
          ),
        if (onRating != null) ...[
          const PopupMenuDivider(),
          PopupMenuItem(
            enabled: false,
            child: Text(l.minimumRating, style: labelStyle),
          ),
          for (final r in _ratingThresholds)
            CheckedPopupMenuItem(
              value: _RatingChoice(r),
              checked: r == minRating,
              child: Text(
                r == 0 ? l.ratingAny : l.ratingAtLeast(r.toStringAsFixed(0)),
              ),
            ),
        ],
      ],
    );
  }
}

/// One selectable entry in the sort/filter menu. A sealed hierarchy lets the
/// menu mix sort and rating options under a single value type and dispatch
/// back to the right callback on selection.
sealed class _SortFilterChoice {
  const _SortFilterChoice();
  void apply(SortFilterButton button);
}

class _SortChoice extends _SortFilterChoice {
  final BrowseSort sort;
  const _SortChoice(this.sort);
  @override
  void apply(SortFilterButton button) => button.onSortChanged(sort);
}

class _RatingChoice extends _SortFilterChoice {
  final double minRating;
  const _RatingChoice(this.minRating);
  @override
  void apply(SortFilterButton button) =>
      button.onMinRatingChanged?.call(minRating);
}
