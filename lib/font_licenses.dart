import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Each bundled font family mapped to its SIL Open Font License text asset.
///
/// The keys must match the `family` values in [kFontChoices]/pubspec.yaml
/// exactly (a test enforces this). Fonts added through pubspec.yaml are NOT
/// registered with Flutter's [LicenseRegistry] automatically, so without the
/// wiring below they'd be absent from the app's Licenses page - and OFL-1.1
/// requires the license text to accompany the fonts.
const fontLicenseAssets = <String, String>{
  'Lato': 'assets/fonts/licenses/Lato-OFL.txt',
  'IBM Plex Sans Arabic': 'assets/fonts/licenses/IBMPlexSansArabic-OFL.txt',
  'Atkinson Hyperlegible': 'assets/fonts/licenses/AtkinsonHyperlegible-OFL.txt',
  'Space Mono': 'assets/fonts/licenses/SpaceMono-OFL.txt',
  'Tajawal': 'assets/fonts/licenses/Tajawal-OFL.txt',
  'Cairo': 'assets/fonts/licenses/Cairo-OFL.txt',
  'Noto Sans Arabic': 'assets/fonts/licenses/NotoSansArabic-OFL.txt',
};

/// Registers the bundled fonts' OFL licenses so they appear in Flutter's
/// standard license page (`showLicensePage`). Call once at startup.
void registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final entry in fontLicenseAssets.entries) {
      final text = await rootBundle.loadString(entry.value);
      yield LicenseEntryWithLineBreaks(<String>[entry.key], text);
    }
  });
}
