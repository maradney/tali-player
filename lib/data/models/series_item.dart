class SeriesItem {
  final String seriesId;
  final String name;
  final String? coverUrl;
  final String categoryId;

  /// IMDb-style numeric score (e.g. "7.4") - some panels include this
  /// directly in the list response, opportunistic like everywhere else.
  final String? rating;

  /// When the provider last added/updated this series, as a unix epoch in
  /// SECONDS (the "last_modified" field in get_series), or null if the panel
  /// doesn't report it. Drives the Recently Added view.
  final int? addedAt;

  const SeriesItem({
    required this.seriesId,
    required this.name,
    required this.categoryId,
    this.coverUrl,
    this.rating,
    this.addedAt,
  });

  static String? _parseRating(dynamic value) {
    final n = double.tryParse(value?.toString().trim() ?? '');
    return n != null && n > 0 ? n.toString() : null;
  }

  factory SeriesItem.fromJson(Map<String, dynamic> json) {
    return SeriesItem(
      seriesId: json['series_id'].toString(),
      name: json['name']?.toString() ?? 'Unnamed series',
      categoryId: json['category_id']?.toString() ?? '',
      coverUrl: (json['cover'] as String?)?.isNotEmpty == true
          ? json['cover']
          : null,
      rating: _parseRating(json['rating']),
      addedAt: int.tryParse(json['last_modified']?.toString() ?? ''),
    );
  }
}