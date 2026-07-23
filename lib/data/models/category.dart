/// The category id used for M3U entries that declare no `group-title`. Also its
/// stored display name; the UI localizes it via `categoryDisplayName`.
const kUncategorizedCategoryId = 'Uncategorized';

class Category {
  final String categoryId;
  final String categoryName;

  const Category({required this.categoryId, required this.categoryName});

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      // Xtream panels are inconsistent about returning these as strings
      // vs numbers, so always coerce to String defensively.
      categoryId: json['category_id'].toString(),
      categoryName: json['category_name']?.toString() ?? 'Unnamed',
    );
  }
}