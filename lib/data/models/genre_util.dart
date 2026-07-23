/// Splits a free-text genre string into individual genre tokens.
///
/// Panels return genres as a single field that often lists several at once,
/// with no agreed separator — "Action, Adventure", "Comedy | Drama",
/// "Crime/Thriller". This normalizes that into discrete tokens so a genre
/// can be faceted across the whole catalog. Kept Flutter-free so it's cleanly
/// unit-testable and usable from the data layer.
///
/// Splits only on the unambiguous list separators `, / | ;` and newlines —
/// deliberately NOT on `&` or the word "and", which frequently appear inside a
/// single genre name ("Sci-Fi & Fantasy", "Rock and Roll"). Whitespace is
/// collapsed, blanks dropped, and duplicates removed case-insensitively while
/// preserving the first-seen display casing.
List<String> splitGenres(String? raw) {
  if (raw == null) return const [];
  final parts = raw.split(RegExp(r'[,/|;\n]'));
  final seen = <String>{};
  final result = <String>[];
  for (final part in parts) {
    final token = part.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (token.isEmpty) continue;
    if (seen.add(token.toLowerCase())) result.add(token);
  }
  return result;
}
