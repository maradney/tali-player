import 'package:flutter/material.dart';

import '../../data/models/category.dart';
import '../../l10n/app_localizations.dart';
import 'category_label.dart';
import 'category_rail.dart';
import 'layout_breakpoints.dart';

/// Puts a category list next to its content, in whichever shape fits.
///
/// Wide: the [CategoryRail] beside the content, as on Windows.
///
/// Narrow: the rail collapses to a single full-width button naming the current
/// category, which opens the list as a bottom sheet. The rail is a fixed 240px,
/// so on a ~410dp phone it was taking 58% of the screen and squeezing the
/// content into what was left - on Live TV that was narrow enough to render
/// channel names one character per line, straight down the page.
class CategoryPaneLayout extends StatelessWidget {
  final List<Category> categories;
  final Category? selected;
  final ValueChanged<Category> onSelect;
  final bool Function(Category category)? isLocked;
  final void Function(Category category)? onLongPress;

  /// The pane beside (or below) the categories.
  final Widget child;

  const CategoryPaneLayout({
    super.key,
    required this.categories,
    required this.selected,
    required this.onSelect,
    required this.child,
    this.isLocked,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= kWideLayoutBreakpoint) {
          return Row(
            children: [
              CategoryRail(
                categories: categories,
                selected: selected,
                onSelect: onSelect,
                isLocked: isLocked,
                onLongPress: onLongPress,
              ),
              const VerticalDivider(width: 1),
              Expanded(child: child),
            ],
          );
        }
        return Column(
          children: [
            _CategorySelectorButton(
              categories: categories,
              selected: selected,
              onSelect: onSelect,
              isLocked: isLocked,
              onLongPress: onLongPress,
            ),
            const Divider(height: 1),
            Expanded(child: child),
          ],
        );
      },
    );
  }
}

/// The filter row that sits above a [CategoryPaneLayout], matching its shape.
///
/// Wide: the category filter lines up over the rail, the item filter over the
/// content. Narrow: only the item filter is shown, full width - the category
/// filter would otherwise be pinned to the rail's 240px and leave the item
/// filter about 170px, which truncated its hint to "Filt...". Categories are
/// filtered inside the sheet instead, where the whole width is available.
class CategoryPaneFilters extends StatelessWidget {
  final Widget categoryFilter;
  final Widget itemFilter;

  const CategoryPaneFilters({
    super.key,
    required this.categoryFilter,
    required this.itemFilter,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < kWideLayoutBreakpoint) return itemFilter;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(width: CategoryRail.width, child: categoryFilter),
            const VerticalDivider(width: 1),
            Expanded(child: itemFilter),
          ],
        );
      },
    );
  }
}

/// The narrow-width stand-in for the rail: shows which category is open and
/// opens the full list as a sheet when tapped.
class _CategorySelectorButton extends StatelessWidget {
  final List<Category> categories;
  final Category? selected;
  final ValueChanged<Category> onSelect;
  final bool Function(Category category)? isLocked;
  final void Function(Category category)? onLongPress;

  const _CategorySelectorButton({
    required this.categories,
    required this.selected,
    required this.onSelect,
    this.isLocked,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final current = selected;
    return InkWell(
      onTap: categories.isEmpty ? null : () => _openSheet(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.folder_outlined, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                current == null
                    ? l.selectCategory
                    : categoryDisplayName(current, l),
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }

  Future<void> _openSheet(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => _CategorySheet(
          categories: categories,
          selected: selected,
          onSelect: onSelect,
          isLocked: isLocked,
          onLongPress: onLongPress,
        ),
      );
}

/// The category list as a bottom sheet, with its own filter - a playlist can
/// carry hundreds of categories, so scrolling alone is not enough.
class _CategorySheet extends StatefulWidget {
  final List<Category> categories;
  final Category? selected;
  final ValueChanged<Category> onSelect;
  final bool Function(Category category)? isLocked;
  final void Function(Category category)? onLongPress;

  const _CategorySheet({
    required this.categories,
    required this.selected,
    required this.onSelect,
    this.isLocked,
    this.onLongPress,
  });

  @override
  State<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends State<_CategorySheet> {
  final _filter = TextEditingController();

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  List<Category> _visible(AppLocalizations l) {
    final query = _filter.text.trim().toLowerCase();
    if (query.isEmpty) return widget.categories;
    return [
      for (final c in widget.categories)
        if (categoryDisplayName(c, l).toLowerCase().contains(query)) c,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final visible = _visible(l);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (context, scrollController) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _filter,
              autofocus: false,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: l.filterCategories,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              itemCount: visible.length,
              itemBuilder: (context, index) {
                final category = visible[index];
                final isSelected =
                    category.categoryId == widget.selected?.categoryId;
                final locked = widget.isLocked?.call(category) ?? false;
                return ListTile(
                  selected: isSelected,
                  title: Text(categoryDisplayName(category, l)),
                  trailing: locked
                      ? Icon(Icons.lock,
                          size: 18, color: Theme.of(context).disabledColor)
                      : null,
                  onTap: () {
                    Navigator.pop(context);
                    widget.onSelect(category);
                  },
                  // Long-press toggles the parental lock, same as the rail.
                  // The sheet stays open: locking several categories in a row
                  // is the common case, and reopening it each time would make
                  // that tedious.
                  onLongPress: widget.onLongPress == null
                      ? null
                      : () => widget.onLongPress!(category),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
