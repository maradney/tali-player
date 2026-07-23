import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final service = SettingsService.instance;

  // Settings are now per-profile. Loading for the 'default' profile also picks
  // up the legacy (unprefixed) keys pre-profiles builds wrote, so the
  // seed-then-load tests below keep exercising that path.
  const pid = 'default';

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    service.resetForTesting();
  });

  test('defaults to dark when nothing is saved', () async {
    await service.loadFor(pid);
    expect(service.themeMode, ThemeMode.dark);
  });

  test('load restores a saved theme mode', () async {
    SharedPreferences.setMockInitialValues({'settings_theme_mode': 'light'});
    await service.loadFor(pid);
    expect(service.themeMode, ThemeMode.light);
  });

  test('setThemeMode updates, persists, and notifies', () async {
    await service.loadFor(pid);
    var notified = 0;
    void listener() => notified++;
    service.addListener(listener);

    await service.setThemeMode(ThemeMode.light);
    expect(service.themeMode, ThemeMode.light);
    expect(notified, 1);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('settings_theme_mode_$pid'), 'light');

    service.removeListener(listener);
  });

  test('setThemeMode is a no-op (no notify) when unchanged', () async {
    SharedPreferences.setMockInitialValues({'settings_theme_mode': 'system'});
    await service.loadFor(pid);
    var notified = 0;
    void listener() => notified++;
    service.addListener(listener);

    await service.setThemeMode(ThemeMode.system);
    expect(notified, 0);

    service.removeListener(listener);
  });

  group('theme preset', () {
    test('defaults to the first preset when nothing is saved', () async {
      await service.loadFor(pid);
      expect(service.themePreset.id, kThemePresets.first.id);
    });

    test('load restores a saved preset by id', () async {
      final target = kThemePresets[2];
      SharedPreferences.setMockInitialValues({'settings_theme_preset': target.id});
      await service.loadFor(pid);
      expect(service.themePreset.id, target.id);
    });

    test('an unrecognized saved id falls back to the default preset', () async {
      SharedPreferences.setMockInitialValues(
          {'settings_theme_preset': 'no-such-preset'});
      await service.loadFor(pid);
      expect(service.themePreset.id, kThemePresets.first.id);
    });

    test('setThemePreset updates, persists, and notifies', () async {
      await service.loadFor(pid);
      var notified = 0;
      void listener() => notified++;
      service.addListener(listener);

      final target = kThemePresets[3];
      await service.setThemePreset(target);
      expect(service.themePreset.id, target.id);
      expect(notified, 1);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('settings_theme_preset_$pid'), target.id);

      service.removeListener(listener);
    });

    test('setThemePreset is a no-op (no notify) when unchanged', () async {
      SharedPreferences.setMockInitialValues(
          {'settings_theme_preset': kThemePresets.first.id});
      await service.loadFor(pid);
      var notified = 0;
      void listener() => notified++;
      service.addListener(listener);

      await service.setThemePreset(kThemePresets.first);
      expect(notified, 0);

      service.removeListener(listener);
    });

    test('every preset id is unique', () {
      final ids = kThemePresets.map((p) => p.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
    });
  });

  group('font choice', () {
    test('defaults to the system font (null family) when nothing is saved',
        () async {
      await service.loadFor(pid);
      expect(service.fontChoice.id, kFontChoices.first.id);
      expect(service.fontFamily, isNull);
    });

    test('load restores a saved font by id, exposing its family', () async {
      final ibm = kFontChoices.firstWhere((f) => f.id == 'ibm_plex_sans_arabic');
      SharedPreferences.setMockInitialValues({'settings_font': ibm.id});
      await service.loadFor(pid);
      expect(service.fontChoice.id, ibm.id);
      expect(service.fontFamily, 'IBM Plex Sans Arabic');
    });

    test('an unrecognized saved id falls back to the system default', () async {
      SharedPreferences.setMockInitialValues({'settings_font': 'no-such-font'});
      await service.loadFor(pid);
      expect(service.fontChoice.id, kFontChoices.first.id);
      expect(service.fontFamily, isNull);
    });

    test('setFontChoice updates, persists, and notifies', () async {
      await service.loadFor(pid);
      var notified = 0;
      void listener() => notified++;
      service.addListener(listener);

      final target = kFontChoices.firstWhere((f) => f.id == 'space_mono');
      await service.setFontChoice(target);
      expect(service.fontChoice.id, target.id);
      expect(service.fontFamily, 'Space Mono');
      expect(notified, 1);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('settings_font_$pid'), target.id);

      service.removeListener(listener);
    });

    test('setFontChoice is a no-op (no notify) when unchanged', () async {
      SharedPreferences.setMockInitialValues(
          {'settings_font': kFontChoices.first.id});
      await service.loadFor(pid);
      var notified = 0;
      void listener() => notified++;
      service.addListener(listener);

      await service.setFontChoice(kFontChoices.first);
      expect(notified, 0);

      service.removeListener(listener);
    });

    test('the requested IBM Plex Sans Arabic font is available', () {
      expect(
        kFontChoices.any((f) => f.family == 'IBM Plex Sans Arabic'),
        isTrue,
      );
    });

    test('the added Arabic families are available, at the end of the list', () {
      const arabic = ['Noto Sans Arabic', 'Tajawal', 'Cairo'];
      for (final family in arabic) {
        expect(kFontChoices.any((f) => f.family == family), isTrue,
            reason: '$family should be offered');
      }
      // They were requested to sit at the end of the picker.
      final lastThree =
          kFontChoices.sublist(kFontChoices.length - 3).map((f) => f.family);
      expect(lastThree, arabic);
    });

    test('every font id is unique', () {
      final ids = kFontChoices.map((f) => f.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
    });
  });

  group('grid density', () {
    test('defaults to comfortable when nothing is saved', () async {
      await service.loadFor(pid);
      expect(service.gridDensity, GridDensity.comfortable);
    });

    test('ideal tile width grows monotonically with density', () {
      final compact = gridIdealTileWidthOf(GridDensity.compact);
      final comfortable = gridIdealTileWidthOf(GridDensity.comfortable);
      final spacious = gridIdealTileWidthOf(GridDensity.spacious);
      expect(compact, lessThan(comfortable));
      expect(comfortable, lessThan(spacious));
      // Comfortable preserves the pre-setting default.
      expect(comfortable, 200);
    });

    test('gridIdealTileWidth reflects the current density', () async {
      SharedPreferences.setMockInitialValues(
          {'settings_grid_density': 'compact'});
      await service.loadFor(pid);
      expect(service.gridIdealTileWidth,
          gridIdealTileWidthOf(GridDensity.compact));
    });

    test('load restores a saved density; unknown falls back', () async {
      SharedPreferences.setMockInitialValues(
          {'settings_grid_density': 'spacious'});
      await service.loadFor(pid);
      expect(service.gridDensity, GridDensity.spacious);

      SharedPreferences.setMockInitialValues(
          {'settings_grid_density': 'nope'});
      await service.loadFor(pid);
      expect(service.gridDensity, GridDensity.comfortable);
    });

    test('setGridDensity updates, persists, and notifies', () async {
      await service.loadFor(pid);
      var notified = 0;
      void listener() => notified++;
      service.addListener(listener);

      await service.setGridDensity(GridDensity.spacious);
      expect(service.gridDensity, GridDensity.spacious);
      expect(notified, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('settings_grid_density_$pid'), 'spacious');

      service.removeListener(listener);
    });

    test('setGridDensity is a no-op (no notify) when unchanged', () async {
      SharedPreferences.setMockInitialValues(
          {'settings_grid_density': 'compact'});
      await service.loadFor(pid);
      var notified = 0;
      void listener() => notified++;
      service.addListener(listener);

      await service.setGridDensity(GridDensity.compact);
      expect(notified, 0);

      service.removeListener(listener);
    });
  });

  group('per-profile isolation', () {
    test('each profile keeps its own theme, and switching reloads it',
        () async {
      await service.loadFor('p_a');
      await service.setThemeMode(ThemeMode.light);
      await service.setGridDensity(GridDensity.spacious);

      // A different profile starts from defaults, not profile A's values.
      await service.loadFor('p_b');
      expect(service.themeMode, ThemeMode.dark);
      expect(service.gridDensity, GridDensity.comfortable);
      await service.setThemeMode(ThemeMode.system);

      // Back to A: its own saved values are restored intact.
      await service.loadFor('p_a');
      expect(service.themeMode, ThemeMode.light);
      expect(service.gridDensity, GridDensity.spacious);

      // Each profile's value persisted under its own key.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('settings_theme_mode_p_a'), 'light');
      expect(prefs.getString('settings_theme_mode_p_b'), 'system');
    });

    test('deleteFor wipes only that profile\'s settings', () async {
      await service.loadFor('p_keep');
      await service.setThemeMode(ThemeMode.light);
      await service.loadFor('p_drop');
      await service.setThemeMode(ThemeMode.system);

      await service.deleteFor('p_drop');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('settings_theme_mode_p_drop'), isNull);
      expect(prefs.getString('settings_theme_mode_p_keep'), 'light');
    });
  });

  group('enhanced search flag', () {
    test('defaults to off when nothing is saved', () async {
      await service.loadFor(pid);
      expect(service.enhancedSearchEnabled, isFalse);
    });

    test('load restores a saved value from the profile-scoped key', () async {
      SharedPreferences.setMockInitialValues(
          {'settings_enhanced_search_$pid': true});
      await service.loadFor(pid);
      expect(service.enhancedSearchEnabled, isTrue);
    });

    test('setEnhancedSearchEnabled updates, persists, and notifies', () async {
      await service.loadFor(pid);
      var notified = 0;
      void listener() => notified++;
      service.addListener(listener);

      await service.setEnhancedSearchEnabled(true);
      expect(service.enhancedSearchEnabled, isTrue);
      expect(notified, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('settings_enhanced_search_$pid'), isTrue);

      service.removeListener(listener);
    });

    test('is a no-op (no notify) when unchanged', () async {
      await service.loadFor(pid);
      var notified = 0;
      void listener() => notified++;
      service.addListener(listener);

      await service.setEnhancedSearchEnabled(false);
      expect(notified, 0);

      service.removeListener(listener);
    });

    test('is isolated per profile', () async {
      await service.loadFor('p_x');
      await service.setEnhancedSearchEnabled(true);
      await service.loadFor('p_y');
      expect(service.enhancedSearchEnabled, isFalse); // y untouched
      await service.loadFor('p_x');
      expect(service.enhancedSearchEnabled, isTrue); // x restored
    });
  });

  group('external player', () {
    test('defaults: disabled, no path, useExternalPlayer false', () async {
      await service.loadFor(pid);
      expect(service.externalPlayerEnabled, isFalse);
      expect(service.externalPlayerPath, '');
      expect(service.useExternalPlayer, isFalse);
    });

    test('enabled + path persist and drive useExternalPlayer', () async {
      await service.loadFor(pid);
      await service.setExternalPlayerEnabled(true);
      // Flag alone isn't enough — a path is required.
      expect(service.useExternalPlayer, isFalse);
      await service.setExternalPlayerPath(r'C:\VLC\vlc.exe');
      expect(service.useExternalPlayer, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('settings_external_player_enabled_$pid'), isTrue);
      expect(prefs.getString('settings_external_player_path_$pid'),
          r'C:\VLC\vlc.exe');
    });

    test('load restores saved enabled + path', () async {
      SharedPreferences.setMockInitialValues({
        'settings_external_player_enabled_$pid': true,
        'settings_external_player_path_$pid': r'D:\mpv\mpv.exe',
      });
      await service.loadFor(pid);
      expect(service.externalPlayerEnabled, isTrue);
      expect(service.externalPlayerPath, r'D:\mpv\mpv.exe');
      expect(service.useExternalPlayer, isTrue);
    });

    test('is isolated per profile', () async {
      await service.loadFor('p_ext_x');
      await service.setExternalPlayerEnabled(true);
      await service.setExternalPlayerPath(r'C:\VLC\vlc.exe');
      await service.loadFor('p_ext_y');
      expect(service.useExternalPlayer, isFalse); // y untouched
      await service.loadFor('p_ext_x');
      expect(service.externalPlayerPath, r'C:\VLC\vlc.exe'); // x restored
    });
  });

  group('language', () {
    test('defaults to system (null locale) when nothing is saved', () async {
      await service.loadFor(pid);
      expect(service.language, AppLanguage.system);
      expect(service.appLocale, isNull);
    });

    test('arabic maps to an ar locale', () async {
      SharedPreferences.setMockInitialValues({'settings_language': 'arabic'});
      await service.loadFor(pid);
      expect(service.language, AppLanguage.arabic);
      expect(service.appLocale, const Locale('ar'));
    });

    test('english maps to an en locale', () {
      expect(appLanguageLocale(AppLanguage.english), const Locale('en'));
      expect(appLanguageLocale(AppLanguage.system), isNull);
    });

    test('the added languages map to the right locales', () {
      expect(appLanguageLocale(AppLanguage.spanish), const Locale('es'));
      expect(appLanguageLocale(AppLanguage.french), const Locale('fr'));
      expect(appLanguageLocale(AppLanguage.portuguese), const Locale('pt'));
      expect(appLanguageLocale(AppLanguage.german), const Locale('de'));
      expect(appLanguageLocale(AppLanguage.italian), const Locale('it'));
      expect(appLanguageLocale(AppLanguage.turkish), const Locale('tr'));
      expect(appLanguageLocale(AppLanguage.persian), const Locale('fa'));
      expect(appLanguageLocale(AppLanguage.urdu), const Locale('ur'));
      expect(appLanguageLocale(AppLanguage.hindi), const Locale('hi'));
      expect(appLanguageLocale(AppLanguage.indonesian), const Locale('id'));
      expect(appLanguageLocale(AppLanguage.thai), const Locale('th'));
    });

    test('every non-system language has a locale and a non-empty endonym', () {
      for (final lang in AppLanguage.values) {
        expect(languageEndonym(lang).trim(), isNotEmpty);
        if (lang != AppLanguage.system) {
          expect(appLanguageLocale(lang), isNotNull,
              reason: '$lang should map to a locale');
        }
      }
    });

    test('unknown saved value falls back to system', () async {
      SharedPreferences.setMockInitialValues({'settings_language': 'klingon'});
      await service.loadFor(pid);
      expect(service.language, AppLanguage.system);
    });

    test('setLanguage updates, persists, and notifies', () async {
      await service.loadFor(pid);
      var notified = 0;
      void listener() => notified++;
      service.addListener(listener);

      await service.setLanguage(AppLanguage.arabic);
      expect(service.language, AppLanguage.arabic);
      expect(notified, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('settings_language_$pid'), 'arabic');

      service.removeListener(listener);
    });

    test('every non-system font family maps to a bundled asset family', () {
      // Guards against a typo between kFontChoices and pubspec.yaml's fonts:.
      const registered = {
        'Lato',
        'IBM Plex Sans Arabic',
        'Atkinson Hyperlegible',
        'Space Mono',
        'Tajawal',
        'Cairo',
        'Noto Sans Arabic',
      };
      for (final choice in kFontChoices.where((f) => f.family != null)) {
        expect(registered, contains(choice.family));
      }
    });
  });
}
