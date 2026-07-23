import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/models/catalog_row.dart';
import 'package:iptv_player/data/models/search_result.dart';
import 'package:iptv_player/features/search/search_screen.dart';

/// A minimal SearchResult built via CatalogRow (pure — no DB) with a category.
SearchResult _res(String id, ContentType type, {String cat = '1'}) => CatalogRow(
      accountKey: 'k',
      type: type,
      id: id,
      name: 'name-$id',
      categoryId: cat,
    ).toSearchResult();

void main() {
  group('visibleSearchResults', () {
    bool noneLocked(SearchResult _) => false;

    test('passes everything through when nothing is category-locked', () {
      final results = <Object>[
        ContentType.movie,
        _res('1', ContentType.movie),
        _res('2', ContentType.movie),
      ];
      expect(visibleSearchResults(results, noneLocked), results);
    });

    test('drops rows whose category is locked', () {
      final results = <Object>[
        _res('1', ContentType.movie, cat: 'a'),
        _res('2', ContentType.movie, cat: 'b'),
      ];
      final visible = visibleSearchResults(results, (r) => r.categoryId == 'a');
      expect(visible.map((o) => (o as SearchResult).id), ['2']);
    });

    test('keeps a section header that still has a result after it', () {
      final results = <Object>[
        ContentType.movie,
        _res('1', ContentType.movie, cat: 'a'),
        _res('2', ContentType.movie, cat: 'b'),
      ];
      final visible = visibleSearchResults(results, (r) => r.categoryId == 'a');
      expect(visible.first, ContentType.movie);
      expect((visible[1] as SearchResult).id, '2');
      expect(visible.length, 2);
    });

    test('drops a section header left empty after filtering', () {
      final results = <Object>[
        ContentType.movie,
        _res('1', ContentType.movie, cat: 'b'),
        ContentType.series,
        _res('2', ContentType.series, cat: 'a'), // only series result, locked
      ];
      final visible = visibleSearchResults(results, (r) => r.categoryId == 'a');
      // Series section header is pruned; movie section + its row remain.
      expect(visible, [ContentType.movie, isA<SearchResult>()]);
      expect((visible[1] as SearchResult).id, '1');
    });

    test('everything locked collapses to empty (headers pruned too)', () {
      final results = <Object>[
        ContentType.movie,
        _res('1', ContentType.movie, cat: 'a'),
        ContentType.series,
        _res('2', ContentType.series, cat: 'a'),
      ];
      expect(visibleSearchResults(results, (_) => true), isEmpty);
    });

    test('empty input yields empty output', () {
      expect(visibleSearchResults(const [], noneLocked), isEmpty);
    });
  });
}
