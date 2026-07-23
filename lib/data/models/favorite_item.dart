/// A favorited item, one of live/movie/series. We store a small snapshot
/// (name, image, and type-specific extras) rather than just an id, so the
/// Favorites screen can render instantly without re-fetching from the API.
class FavoriteItem {
  final String type; // 'live' | 'movie' | 'series'
  final String id;
  final String name;
  final String? imageUrl;
  // Nullable for backward compatibility with favorites saved before this
  // field existed - lets category-level PIN locks be checked from screens
  // (Favorites/Search/Watch History) that only hold a denormalized snapshot
  // rather than the original Channel/Movie/SeriesItem.
  final String? categoryId;
  final Map<String, dynamic> extra; // e.g. movie needs containerExtension

  const FavoriteItem({
    required this.type,
    required this.id,
    required this.name,
    this.imageUrl,
    this.categoryId,
    this.extra = const {},
  });

  /// Unique key across all favorite types, e.g. "movie:1234".
  String get key => '$type:$id';

  Map<String, dynamic> toJson() => {
        'type': type,
        'id': id,
        'name': name,
        'imageUrl': imageUrl,
        'categoryId': categoryId,
        'extra': extra,
      };

  factory FavoriteItem.fromJson(Map<String, dynamic> json) {
    return FavoriteItem(
      type: json['type'] as String,
      id: json['id'] as String,
      name: json['name'] as String,
      imageUrl: json['imageUrl'] as String?,
      categoryId: json['categoryId'] as String?,
      extra: (json['extra'] as Map?)?.cast<String, dynamic>() ?? {},
    );
  }
}