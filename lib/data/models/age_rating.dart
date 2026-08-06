/// Normalises a panel's age-rating field, returning null when it carries no
/// information.
///
/// Panels are inconsistent here: as well as leaving the field blank, they
/// return bare punctuation like "+" or "-", or placeholders like "N/A". The
/// detail screens render this as a chip next to the title, so a value like "+"
/// becomes an unlabelled badge that looks like a broken button - which is
/// exactly how it read on the Android build before this existed.
///
/// The rule is deliberately narrow: a rating must contain at least one letter
/// or digit, plus a short list of known placeholders is rejected. Anything
/// else is passed through untouched, because real ratings vary wildly by
/// country ("12", "PG-13", "18+", "TV-MA", "‏+16") and guessing at a format
/// would drop legitimate ones. "Unrated" is kept: that is a real statement
/// about a title, unlike "N/A" which just means the panel has no value.
String? meaningfulAgeRating(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  // No letter or digit anywhere - "+", "-", "()", and friends.
  //
  // \p{N} rather than [0-9]: an Arabic panel can return "١٦", whose digits are
  // Unicode Nd but not ASCII, and dropping those would quietly discard real
  // ratings in exactly the locales this app goes out of its way to support.
  if (!RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(trimmed)) return null;
  const placeholders = {'n/a', 'na', 'n.a.', 'none', 'null', 'undefined', '-'};
  if (placeholders.contains(trimmed.toLowerCase())) return null;
  return trimmed;
}
