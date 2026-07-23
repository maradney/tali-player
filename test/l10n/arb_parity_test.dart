import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards that every locale ARB carries a translation for every message in the
/// English template. gen-l10n only warns about untranslated messages; this
/// turns that into a hard failure so a new string can't silently ship as
/// English in the other 12 languages. Runs against the raw ARB files (not the
/// generated Dart) so it fails fast without a build step.
void main() {
  final dir = Directory('lib/l10n');

  // Template message keys: everything except the "@"-prefixed metadata and the
  // "@@locale" marker.
  Set<String> messageKeys(Map<String, dynamic> arb) =>
      arb.keys.where((k) => !k.startsWith('@')).toSet();

  Map<String, dynamic> readArb(String locale) => jsonDecode(
        File('lib/l10n/app_$locale.arb').readAsStringSync(),
      ) as Map<String, dynamic>;

  final templateKeys = messageKeys(readArb('en'));

  // Discover the shipped locales from the ARB files on disk rather than
  // hard-coding them, so adding a language is automatically covered.
  final locales = dir
      .listSync()
      .whereType<File>()
      .map((f) => RegExp(r'app_([a-z]+)\.arb$').firstMatch(f.path)?.group(1))
      .whereType<String>()
      .where((l) => l != 'en')
      .toList();

  test('every translated ARB exists for the expected locales', () {
    // Sanity check that discovery worked and the full set is present.
    expect(locales.toSet(), {
      'ar', 'es', 'fr', 'pt', 'de', 'it', 'tr', 'fa', 'ur', 'hi', 'id', 'th',
    });
  });

  for (final locale in locales) {
    test('$locale translates every template message', () {
      final keys = messageKeys(readArb(locale));
      final missing = templateKeys.difference(keys);
      expect(missing, isEmpty,
          reason: 'app_$locale.arb is missing: ${missing.join(', ')}');
    });
  }
}
