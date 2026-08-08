import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/services/settings_service.dart';
import 'package:iptv_player/features/common/poster_grid.dart';

/// Column count per density. The grid-density setting silently did nothing on
/// narrow windows: rounding up meant Comfortable and Spacious both landed on
/// the same column count, so two of the three options rendered identically.
void main() {
  int columns(double available, GridDensity density) =>
      PosterGrid.posterColumnsFor(available, gridIdealTileWidthOf(density));

  /// A phone: 411dp wide, less the grid's 12pt padding either side.
  const phone = 411.0 - 24;

  /// A desktop window narrow enough to have hit the same collision.
  const narrowDesktop = 800.0 - 24;

  const wideDesktop = 1600.0 - 24;

  test('the three densities differ on a phone', () {
    final compact = columns(phone, GridDensity.compact);
    final comfortable = columns(phone, GridDensity.comfortable);
    final spacious = columns(phone, GridDensity.spacious);

    expect(compact, greaterThan(comfortable),
        reason: 'compact=$compact comfortable=$comfortable');
    expect(comfortable, greaterThan(spacious),
        reason: 'comfortable=$comfortable spacious=$spacious');
  });

  test('the three densities differ on a narrow desktop window', () {
    // Not an Android-only bug: ceil() collided here too (4, 4).
    final compact = columns(narrowDesktop, GridDensity.compact);
    final comfortable = columns(narrowDesktop, GridDensity.comfortable);
    final spacious = columns(narrowDesktop, GridDensity.spacious);

    expect(compact, greaterThan(comfortable));
    expect(comfortable, greaterThan(spacious));
  });

  test('the three densities still differ on a wide window', () {
    expect(columns(wideDesktop, GridDensity.compact),
        greaterThan(columns(wideDesktop, GridDensity.comfortable)));
    expect(columns(wideDesktop, GridDensity.comfortable),
        greaterThan(columns(wideDesktop, GridDensity.spacious)));
  });

  test('denser settings never show fewer columns, at any width', () {
    // Sweep rather than spot-check: the ordering must hold everywhere, not
    // just at the sizes that happened to be tested.
    for (var width = 200.0; width <= 2400; width += 1) {
      final compact = columns(width, GridDensity.compact);
      final comfortable = columns(width, GridDensity.comfortable);
      final spacious = columns(width, GridDensity.spacious);
      expect(compact, greaterThanOrEqualTo(comfortable), reason: 'w=$width');
      expect(comfortable, greaterThanOrEqualTo(spacious), reason: 'w=$width');
    }
  });

  test('always at least one column, even at silly sizes', () {
    // A grid with zero columns would divide by zero working out tile width.
    expect(PosterGrid.posterColumnsFor(0, 200), 1);
    expect(PosterGrid.posterColumnsFor(-50, 200), 1);
    expect(PosterGrid.posterColumnsFor(10, 200), 1);
    expect(PosterGrid.posterColumnsFor(400, 0), 1);
  });
}
