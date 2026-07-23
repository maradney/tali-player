import 'dart:convert';

import 'account.dart';
import 'channel.dart';
import 'movie.dart';
import 'search_result.dart';
import 'series_item.dart';

/// A row in the local SQLite search index. Stores a snapshot of one
/// live/movie/series item - enough to display it AND to reconstruct the
/// original Channel/Movie/SeriesItem object for playback/navigation
/// without hitting the network again.
class CatalogRow {
  final String accountKey;
  final ContentType type;
  final String id;
  final String name;
  final String? imageUrl;
  final String categoryId;
  final Map<String, dynamic> extra; // e.g. movie needs containerExtension

  /// Unix epoch in SECONDS when the provider added this item (movies' "added"
  /// / series' "last_modified"), or null when the panel doesn't report it.
  /// Its own indexed column (not [extra]) so Recently Added can ORDER BY it.
  final int? addedAt;

  /// Four-digit release year, or null. Filled in only by enhanced-search
  /// enrichment (the category list doesn't carry it), never written back by
  /// [toDbMap] — set via CatalogDatabase.saveEnrichment.
  final int? year;

  const CatalogRow({
    required this.accountKey,
    required this.type,
    required this.id,
    required this.name,
    required this.categoryId,
    this.imageUrl,
    this.extra = const {},
    this.addedAt,
    this.year,
  });

  /// Deterministic key an Account maps to - shared with FavoritesService's
  /// convention so both features key their storage the same way.
  static String accountKeyFor(Account account) => account.key;

  Map<String, Object?> toDbMap() => {
        'account_key': accountKey,
        'type': type.name,
        'id': id,
        'name': name,
        'image_url': imageUrl,
        'category_id': categoryId,
        'extra': extra.isEmpty ? null : jsonEncode(extra),
        'added_at': addedAt,
      };

  static CatalogRow fromDbMap(Map<String, Object?> map) {
    final extra = map['extra'] != null
        ? (jsonDecode(map['extra'] as String) as Map).cast<String, dynamic>()
        : <String, dynamic>{};
    // Enrichment may have found a rating the category list didn't have; surface
    // it through extra['rating'] (what toSearchResult reads) without letting it
    // override a rating the list already provided.
    final detailRating = map['detail_rating'] as String?;
    if (detailRating != null && extra['rating'] == null) {
      extra['rating'] = detailRating;
    }
    return CatalogRow(
      accountKey: map['account_key'] as String,
      type: ContentType.values.byName(map['type'] as String),
      id: map['id'] as String,
      name: map['name'] as String,
      imageUrl: map['image_url'] as String?,
      categoryId: map['category_id'] as String? ?? '',
      extra: extra,
      addedAt: map['added_at'] as int?,
      year: map['year'] as int?,
    );
  }

  /// Rebuilds the original typed object so the UI can navigate to
  /// playback/detail exactly like it would from a live API response.
  SearchResult toSearchResult() {
    final dynamic raw;
    final rating = extra['rating'] as String?;
    switch (type) {
      case ContentType.live:
        raw = Channel(
          streamId: id,
          name: name,
          categoryId: categoryId,
          logoUrl: imageUrl,
          // Present only for M3U rows; Xtream builds its URL from the account.
          url: extra['url'] as String?,
          headers: castHeaders(extra['headers']),
        );
        break;
      case ContentType.movie:
        raw = Movie(
          streamId: id,
          name: name,
          categoryId: categoryId,
          containerExtension: extra['containerExtension'] as String? ?? 'mp4',
          posterUrl: imageUrl,
          rating: rating,
          url: extra['url'] as String?,
        );
        break;
      case ContentType.series:
        raw = SeriesItem(
          seriesId: id,
          name: name,
          categoryId: categoryId,
          coverUrl: imageUrl,
          rating: rating,
        );
        break;
    }
    return SearchResult(
      type: type,
      id: id,
      name: name,
      imageUrl: imageUrl,
      rating: rating,
      categoryId: categoryId,
      raw: raw,
    );
  }
}