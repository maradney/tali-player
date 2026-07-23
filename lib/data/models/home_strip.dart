import 'search_result.dart';

/// The kinds of rail the Home dashboard can show. Built-in kinds draw from
/// their own service/query; [category] is a user-added rail showing one
/// catalog category's items.
enum HomeStripType {
  continueWatching,
  watchlist,
  recentlyAdded,
  downloads,
  favorites,
  category,
}

/// One configurable Home rail: what it shows, whether it's currently enabled,
/// and (for [HomeStripType.category] only) which category it points at.
/// The list order IS the display order.
class HomeStrip {
  final HomeStripType type;
  final bool enabled;

  /// Category strips only: the content type the category belongs to.
  final ContentType? categoryType;

  /// Category strips only: the category's id in the catalog.
  final String? categoryId;

  /// Category strips only: the display name snapshotted at pick time (Home is
  /// local-only — it must not need an API call to label a rail).
  final String? categoryName;

  const HomeStrip({
    required this.type,
    this.enabled = true,
    this.categoryType,
    this.categoryId,
    this.categoryName,
  });

  /// Stable identity for toggling/reordering/removal. Built-in strips exist
  /// once; category strips are keyed by what they point at.
  String get key => type == HomeStripType.category
      ? 'category:${categoryType?.name}:$categoryId'
      : type.name;

  HomeStrip copyWith({bool? enabled}) => HomeStrip(
        type: type,
        enabled: enabled ?? this.enabled,
        categoryType: categoryType,
        categoryId: categoryId,
        categoryName: categoryName,
      );

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'enabled': enabled,
        if (categoryType != null) 'categoryType': categoryType!.name,
        if (categoryId != null) 'categoryId': categoryId,
        if (categoryName != null) 'categoryName': categoryName,
      };

  /// Null for an unrecognized stored type (e.g. a config written by a newer
  /// app version) — the caller skips it rather than crashing.
  static HomeStrip? fromJson(Map<String, dynamic> json) {
    final type = HomeStripType.values
        .where((t) => t.name == json['type'])
        .firstOrNull;
    if (type == null) return null;
    ContentType? categoryType;
    if (json['categoryType'] != null) {
      categoryType = ContentType.values
          .where((t) => t.name == json['categoryType'])
          .firstOrNull;
    }
    if (type == HomeStripType.category &&
        (categoryType == null || json['categoryId'] == null)) {
      return null; // a category strip without its category is meaningless
    }
    return HomeStrip(
      type: type,
      enabled: json['enabled'] as bool? ?? true,
      categoryType: categoryType,
      categoryId: json['categoryId'] as String?,
      categoryName: json['categoryName'] as String?,
    );
  }

  /// The out-of-the-box configuration: every built-in rail, enabled, in the
  /// order the dashboard always showed them (Favorites, the newest rail,
  /// comes last so existing users' layout doesn't shuffle).
  static const List<HomeStrip> defaults = [
    HomeStrip(type: HomeStripType.continueWatching),
    HomeStrip(type: HomeStripType.watchlist),
    HomeStrip(type: HomeStripType.recentlyAdded),
    HomeStrip(type: HomeStripType.downloads),
    HomeStrip(type: HomeStripType.favorites),
  ];

  /// [stored] in its saved order, with any built-in strip it doesn't know
  /// about yet (added in an app update) appended in default state — so an old
  /// config never silently loses a new rail.
  static List<HomeStrip> withDefaults(List<HomeStrip> stored) {
    final present = {for (final s in stored) s.key};
    return [
      ...stored,
      for (final d in defaults)
        if (!present.contains(d.key)) d,
    ];
  }
}
