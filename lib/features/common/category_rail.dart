import 'package:flutter/material.dart';

import '../../data/models/category.dart';
import '../../l10n/app_localizations.dart';
import 'category_label.dart';
import 'tile_highlight.dart';

/// Fixed-width left-hand list of categories - shared by Live TV, Movies,
/// and Series, since all three follow the same categories-first pattern.
class CategoryRail extends StatelessWidget {
  /// Exposed so callers (e.g. a filter field placed above this rail) can
  /// line their own width up with it exactly, instead of duplicating the
  /// magic number and risking the two drifting apart.
  static const width = 240.0;

  final List<Category> categories;
  final Category? selected;
  final ValueChanged<Category> onSelect;
  final bool Function(Category category)? isLocked;
  final void Function(Category category)? onLongPress;

  const CategoryRail({
    super.key,
    required this.categories,
    required this.selected,
    required this.onSelect,
    this.isLocked,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: ListView.builder(
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final category = categories[index];
          final isSelected = category.categoryId == selected?.categoryId;
          final locked = isLocked?.call(category) ?? false;
          return TileHighlight(
            highlighted: isSelected,
            color:
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
            child: ListTile(
              selected: isSelected,
              title: Text(
                categoryDisplayName(category, AppLocalizations.of(context)!),
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              trailing: locked
                  ? Icon(Icons.lock,
                      size: 18, color: Theme.of(context).disabledColor)
                  : null,
              onTap: () => onSelect(category),
              onLongPress:
                  onLongPress == null ? null : () => onLongPress!(category),
            ),
          );
        },
      ),
    );
  }
}
