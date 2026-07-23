/// Client-side ordering + rating filter for the Movies/Series browse grids.
///
/// These act on the already-loaded list for the currently selected category
/// (see [SortFilterButton]), so they work offline and cost no extra API
/// calls. Kept free of Flutter/l10n imports so it's cleanly unit-testable;
/// the human-readable labels live with the button widget.
enum BrowseSort {
  /// The provider's own order, as returned by the panel — the default.
  providerDefault,
  nameAsc,
  nameDesc,
  ratingDesc,
  recentlyAdded,
}

/// Returns a new list ordered by [sort], leaving [items] untouched.
///
/// [ratingOf] is the raw string score (e.g. "7.4") or null; [addedAtOf] is a
/// unix-seconds timestamp or null. Items missing the sort key sink to the
/// bottom (rating/added treated as -1). Ties keep the provider's original
/// order — the sort is made stable via the original index, since Dart's
/// [List.sort] is not guaranteed stable.
List<T> sortBrowseItems<T>(
  List<T> items, {
  required BrowseSort sort,
  required String Function(T) nameOf,
  required String? Function(T) ratingOf,
  required int? Function(T) addedAtOf,
}) {
  if (sort == BrowseSort.providerDefault) return List<T>.of(items);

  double ratingValue(T i) => double.tryParse(ratingOf(i)?.trim() ?? '') ?? -1;

  final indices = List<int>.generate(items.length, (i) => i);
  indices.sort((ai, bi) {
    final a = items[ai];
    final b = items[bi];
    final c = switch (sort) {
      BrowseSort.nameAsc =>
        nameOf(a).toLowerCase().compareTo(nameOf(b).toLowerCase()),
      BrowseSort.nameDesc =>
        nameOf(b).toLowerCase().compareTo(nameOf(a).toLowerCase()),
      BrowseSort.ratingDesc => ratingValue(b).compareTo(ratingValue(a)),
      BrowseSort.recentlyAdded =>
        (addedAtOf(b) ?? -1).compareTo(addedAtOf(a) ?? -1),
      BrowseSort.providerDefault => 0,
    };
    return c != 0 ? c : ai.compareTo(bi);
  });
  return [for (final i in indices) items[i]];
}

/// Keeps only items whose numeric rating is at least [minRating].
///
/// A [minRating] of 0 (or less) keeps everything, including unrated items;
/// any positive threshold drops items with no parseable rating.
List<T> filterByMinRating<T>(
  List<T> items,
  double minRating, {
  required String? Function(T) ratingOf,
}) {
  if (minRating <= 0) return List<T>.of(items);
  return items.where((i) {
    final r = double.tryParse(ratingOf(i)?.trim() ?? '');
    return r != null && r >= minRating;
  }).toList();
}
