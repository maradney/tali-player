import '../../data/models/category.dart';
import '../../l10n/app_localizations.dart';

/// The display name for a category, localizing the M3U "Uncategorized" sentinel
/// (whose stored name is a fixed English string). Every other category keeps
/// its provider-given name.
String categoryDisplayName(Category category, AppLocalizations l) =>
    category.categoryId == kUncategorizedCategoryId
        ? l.uncategorized
        : category.categoryName;
