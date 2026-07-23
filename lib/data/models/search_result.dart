enum ContentType { live, movie, series }

/// One entry in the searchable catalog. [raw] holds the original
/// Channel/Movie/SeriesItem object so the search screen can navigate
/// to playback/detail without needing to refetch it.
class SearchResult {
  final ContentType type;
  final String id;
  final String name;
  final String? imageUrl;
  final String? rating;

  /// The category this item belongs to - surfaced as a typed field (rather
  /// than digging it out of [raw] with a dynamic cast) so category-level
  /// PIN lock checks stay compile-time safe.
  final String? categoryId;
  final dynamic raw;

  const SearchResult({
    required this.type,
    required this.id,
    required this.name,
    required this.raw,
    this.imageUrl,
    this.rating,
    this.categoryId,
  });
}