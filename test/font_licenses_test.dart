import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/services/settings_service.dart';
import 'package:iptv_player/font_licenses.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every bundled font family has a loadable OFL license asset', () async {
    for (final entry in fontLicenseAssets.entries) {
      final text = await rootBundle.loadString(entry.value);
      expect(text.trim(), isNotEmpty, reason: '${entry.key} license is empty');
      expect(text, contains('Open Font License'),
          reason: '${entry.key} should carry the SIL OFL text');
    }
  });

  test('the license map covers exactly the non-system font choices', () {
    // Adding a font without a license file (or vice versa) fails here rather
    // than silently shipping an unattributed font.
    final families = kFontChoices
        .where((f) => f.family != null)
        .map((f) => f.family)
        .toSet();
    expect(fontLicenseAssets.keys.toSet(), families);
  });
}
