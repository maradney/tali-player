import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/features/common/browse_sort.dart';

/// A tiny stand-in for a browse item (Movie/SeriesItem) carrying just the
/// fields the sort/filter helpers read.
class _Item {
  final String name;
  final String? rating;
  final int? addedAt;
  const _Item(this.name, {this.rating, this.addedAt});
}

List<String> _names(List<_Item> items) => [for (final i in items) i.name];

List<_Item> _sorted(List<_Item> items, BrowseSort sort) => sortBrowseItems(
      items,
      sort: sort,
      nameOf: (i) => i.name,
      ratingOf: (i) => i.rating,
      addedAtOf: (i) => i.addedAt,
    );

void main() {
  final sample = <_Item>[
    const _Item('Banana', rating: '7.0', addedAt: 300),
    const _Item('apple', rating: '9.2', addedAt: 100),
    const _Item('Cherry', rating: null, addedAt: 200),
    const _Item('date', rating: '5.5', addedAt: null),
  ];

  group('sortBrowseItems', () {
    test('providerDefault preserves order and returns a copy', () {
      final result = _sorted(sample, BrowseSort.providerDefault);
      expect(_names(result), _names(sample));
      expect(identical(result, sample), isFalse);
    });

    test('nameAsc / nameDesc are case-insensitive', () {
      expect(_names(_sorted(sample, BrowseSort.nameAsc)),
          ['apple', 'Banana', 'Cherry', 'date']);
      expect(_names(_sorted(sample, BrowseSort.nameDesc)),
          ['date', 'Cherry', 'Banana', 'apple']);
    });

    test('ratingDesc orders high to low; unrated sinks to the bottom', () {
      expect(_names(_sorted(sample, BrowseSort.ratingDesc)),
          ['apple', 'Banana', 'date', 'Cherry']);
    });

    test('recentlyAdded orders newest first; null dates sink', () {
      expect(_names(_sorted(sample, BrowseSort.recentlyAdded)),
          ['Banana', 'Cherry', 'apple', 'date']);
    });

    test('sort is stable — ties keep provider order', () {
      final tied = <_Item>[
        const _Item('first', rating: '8.0'),
        const _Item('second', rating: '8.0'),
        const _Item('third', rating: '8.0'),
      ];
      expect(_names(_sorted(tied, BrowseSort.ratingDesc)),
          ['first', 'second', 'third']);
    });
  });

  group('filterByMinRating', () {
    List<String> filtered(double min) => _names(
          filterByMinRating(sample, min, ratingOf: (i) => i.rating),
        );

    test('0 keeps everything including unrated', () {
      expect(filtered(0), _names(sample));
    });

    test('positive threshold drops lower and unrated items', () {
      expect(filtered(7.0), ['Banana', 'apple']);
      expect(filtered(9.0), ['apple']);
    });

    test('returns a copy at the no-op threshold', () {
      final result = filterByMinRating(sample, 0, ratingOf: (i) => i.rating);
      expect(identical(result, sample), isFalse);
    });
  });
}
