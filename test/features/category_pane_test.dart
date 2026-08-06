import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/models/category.dart';
import 'package:iptv_player/features/common/category_pane.dart';
import 'package:iptv_player/features/common/category_rail.dart';
import 'package:iptv_player/l10n/app_localizations.dart';

/// The category pane is what made Live TV unusable on a phone: a fixed 240px
/// rail beside the content on a ~410dp screen left the content pane so narrow
/// that channel names rendered one character per line, straight down the page.
void main() {
  final categories = [
    const Category(categoryId: '1', categoryName: 'Sports'),
    const Category(categoryId: '2', categoryName: 'News'),
    const Category(categoryId: '3', categoryName: 'Kids'),
  ];

  Widget wrap(Widget child, {required Size size}) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(width: size.width, height: size.height, child: child),
          ),
        ),
      );

  // Expands to whatever width the pane gives it, so the width assertion below
  // measures the pane and not the text's own intrinsic size.
  const contentKey = ValueKey('content');
  Widget pane({Category? selected, ValueChanged<Category>? onSelect}) =>
      CategoryPaneLayout(
        categories: categories,
        selected: selected,
        onSelect: onSelect ?? (_) {},
        child: const SizedBox.expand(
          key: contentKey,
          child: Center(child: Text('CONTENT')),
        ),
      );

  group('CategoryPaneLayout', () {
    testWidgets('shows the rail beside the content on a wide window',
        (tester) async {
      await tester.pumpWidget(
          wrap(pane(selected: categories.first), size: const Size(1200, 800)));
      await tester.pumpAndSettle();

      expect(find.byType(CategoryRail), findsOneWidget);
      expect(find.text('CONTENT'), findsOneWidget);
      // All categories visible at once - that is the point of the rail.
      expect(find.text('Sports'), findsOneWidget);
      expect(find.text('News'), findsOneWidget);
    });

    testWidgets('collapses the rail on a phone-width window', (tester) async {
      await tester.pumpWidget(
          wrap(pane(selected: categories.first), size: const Size(410, 800)));
      await tester.pumpAndSettle();

      expect(find.byType(CategoryRail), findsNothing);
      expect(find.text('CONTENT'), findsOneWidget);
    });

    testWidgets('leaves the content the full width on a phone', (tester) async {
      await tester.pumpWidget(
          wrap(pane(selected: categories.first), size: const Size(410, 800)));
      await tester.pumpAndSettle();

      // The regression itself: with the rail present the content got
      // 410 - 240 = 170px. It should now have the lot.
      expect(tester.getSize(find.byKey(contentKey)).width, 410);
    });

    testWidgets('names the open category so it is not just a mystery button',
        (tester) async {
      await tester.pumpWidget(
          wrap(pane(selected: categories[1]), size: const Size(410, 800)));
      await tester.pumpAndSettle();

      expect(find.text('News'), findsOneWidget);
    });

    testWidgets('the collapsed selector opens a picker and reports the choice',
        (tester) async {
      Category? picked;
      await tester.pumpWidget(wrap(
        pane(selected: categories.first, onSelect: (c) => picked = c),
        size: const Size(410, 800),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.arrow_drop_down));
      await tester.pumpAndSettle();
      // The sheet lists the categories that the rail would have.
      expect(find.text('Kids'), findsOneWidget);

      await tester.tap(find.text('Kids'));
      await tester.pumpAndSettle();
      expect(picked?.categoryName, 'Kids');
    });
  });

  group('CategoryPaneFilters', () {
    Widget filters() => const CategoryPaneFilters(
          categoryFilter: Text('CATEGORY FILTER'),
          itemFilter: Text('ITEM FILTER'),
        );

    testWidgets('shows both filters on a wide window', (tester) async {
      await tester.pumpWidget(wrap(filters(), size: const Size(1200, 200)));
      expect(find.text('CATEGORY FILTER'), findsOneWidget);
      expect(find.text('ITEM FILTER'), findsOneWidget);
    });

    testWidgets('drops the category filter on a phone', (tester) async {
      // Side by side at phone width, the category filter was pinned to the
      // rail's 240px and squeezed the item filter's hint down to "Filt...".
      await tester.pumpWidget(wrap(filters(), size: const Size(410, 200)));
      expect(find.text('CATEGORY FILTER'), findsNothing);
      expect(find.text('ITEM FILTER'), findsOneWidget);
    });
  });
}
