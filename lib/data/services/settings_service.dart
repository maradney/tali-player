import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _themeModePrefsKey = 'settings_theme_mode';
const _themePresetPrefsKey = 'settings_theme_preset';
const _fontPrefsKey = 'settings_font';
const _gridDensityPrefsKey = 'settings_grid_density';
const _languagePrefsKey = 'settings_language';
const _enhancedSearchPrefsKey = 'settings_enhanced_search';
const _autoplayNextEpisodePrefsKey = 'settings_autoplay_next_episode';
const _playerVolumePrefsKey = 'settings_player_volume';
const _externalPlayerEnabledPrefsKey = 'settings_external_player_enabled';
const _externalPlayerPathPrefsKey = 'settings_external_player_path';

/// Profile whose settings fall back to the legacy (unprefixed) keys written by
/// pre-profiles builds. Mirrors ProfilesService.defaultProfileId /
/// Account.defaultProfileId; duplicated as a literal to keep this file free of
/// a service-layer import.
const defaultSettingsProfileId = 'default';

/// UI language. [system] follows the device locale; the others force a locale.
/// Persian and Urdu are right-to-left; Flutter mirrors the layout for those
/// automatically based on the locale.
enum AppLanguage {
  system,
  english,
  arabic,
  spanish,
  french,
  portuguese,
  german,
  italian,
  turkish,
  persian,
  urdu,
  hindi,
  indonesian,
  thai,
}

/// The [Locale] a language maps to, or null for "follow the system".
Locale? appLanguageLocale(AppLanguage language) {
  switch (language) {
    case AppLanguage.system:
      return null;
    case AppLanguage.english:
      return const Locale('en');
    case AppLanguage.arabic:
      return const Locale('ar');
    case AppLanguage.spanish:
      return const Locale('es');
    case AppLanguage.french:
      return const Locale('fr');
    case AppLanguage.portuguese:
      return const Locale('pt');
    case AppLanguage.german:
      return const Locale('de');
    case AppLanguage.italian:
      return const Locale('it');
    case AppLanguage.turkish:
      return const Locale('tr');
    case AppLanguage.persian:
      return const Locale('fa');
    case AppLanguage.urdu:
      return const Locale('ur');
    case AppLanguage.hindi:
      return const Locale('hi');
    case AppLanguage.indonesian:
      return const Locale('id');
    case AppLanguage.thai:
      return const Locale('th');
  }
}

/// Each language shown in its own name (endonym), so users can find their
/// language in the picker regardless of the current UI language. [system] has
/// no endonym - the picker uses the localized "System default" label for it.
String languageEndonym(AppLanguage language) {
  switch (language) {
    case AppLanguage.system:
      return 'System';
    case AppLanguage.english:
      return 'English';
    case AppLanguage.arabic:
      return 'العربية';
    case AppLanguage.spanish:
      return 'Español';
    case AppLanguage.french:
      return 'Français';
    case AppLanguage.portuguese:
      return 'Português';
    case AppLanguage.german:
      return 'Deutsch';
    case AppLanguage.italian:
      return 'Italiano';
    case AppLanguage.turkish:
      return 'Türkçe';
    case AppLanguage.persian:
      return 'فارسی';
    case AppLanguage.urdu:
      return 'اردو';
    case AppLanguage.hindi:
      return 'हिन्दी';
    case AppLanguage.indonesian:
      return 'Bahasa Indonesia';
    case AppLanguage.thai:
      return 'ไทย';
  }
}

/// How tightly the poster grids (Movies/Series/Watch History) pack tiles.
enum GridDensity { compact, comfortable, spacious }

/// Ideal poster-tile width for a density, in logical pixels. Smaller means
/// more columns / smaller posters. Pure so it's easy to unit-test and so the
/// grid widget stays decoupled from the settings enum.
double gridIdealTileWidthOf(GridDensity density) {
  switch (density) {
    case GridDensity.compact:
      return 150;
    case GridDensity.comfortable:
      return 200; // the pre-setting default
    case GridDensity.spacious:
      return 260;
  }
}

/// A named accent preset. Material 3 derives an entire ColorScheme from a
/// single seed color, so each "theme" here is just a seed + label; the seed
/// regenerates every accent in the app (selected tiles, buttons, progress
/// bars, etc.) for both the light and dark variants.
class ThemePreset {
  /// Stable key persisted to prefs - keep it constant even if [name] changes.
  final String id;
  final String name;
  final Color seed;

  const ThemePreset({required this.id, required this.name, required this.seed});
}

/// The built-in accent presets, in display order. The first entry is the
/// default for a fresh install or an unrecognized saved value.
const kThemePresets = <ThemePreset>[
  ThemePreset(id: 'indigo', name: 'Indigo', seed: Color(0xFF3F51B5)),
  ThemePreset(id: 'ocean', name: 'Ocean', seed: Color(0xFF00838F)),
  ThemePreset(id: 'aubergine', name: 'Aubergine', seed: Color(0xFF6A1B4D)),
  ThemePreset(id: 'forest', name: 'Forest', seed: Color(0xFF2E7D32)),
  ThemePreset(id: 'sunset', name: 'Sunset', seed: Color(0xFFE64A19)),
  ThemePreset(id: 'ruby', name: 'Ruby', seed: Color(0xFFC2185B)),
  ThemePreset(id: 'gold', name: 'Gold', seed: Color(0xFFF9A825)),
  ThemePreset(id: 'slate', name: 'Slate', seed: Color(0xFF455A64)),
];

/// A selectable UI font. [family] is null for the "System default" choice,
/// which leaves ThemeData's fontFamily unset so the platform default is
/// used; every other choice names a family bundled as an app asset (see
/// pubspec.yaml / assets/fonts). Bundled - not fetched at runtime - so the
/// app stays offline and makes no third-party network calls.
class FontChoice {
  /// Stable key persisted to prefs - keep it constant even if [name] changes.
  final String id;
  final String name;
  final String? family;

  const FontChoice({required this.id, required this.name, this.family});
}

/// The built-in font choices, in display order. The first entry (system
/// default) is used for a fresh install or an unrecognized saved value, and
/// preserves the pre-feature look (no explicit font family).
const kFontChoices = <FontChoice>[
  FontChoice(id: 'system', name: 'System default'),
  FontChoice(id: 'lato', name: 'Lato', family: 'Lato'),
  FontChoice(
      id: 'atkinson_hyperlegible',
      name: 'Atkinson Hyperlegible',
      family: 'Atkinson Hyperlegible'),
  FontChoice(id: 'space_mono', name: 'Space Mono', family: 'Space Mono'),
  // Arabic-first families (also cover Latin), kept at the end of the list.
  FontChoice(
      id: 'ibm_plex_sans_arabic',
      name: 'IBM Plex Sans Arabic',
      family: 'IBM Plex Sans Arabic'),
  FontChoice(
      id: 'noto_sans_arabic',
      name: 'Noto Sans Arabic',
      family: 'Noto Sans Arabic'),
  FontChoice(id: 'tajawal', name: 'Tajawal', family: 'Tajawal'),
  FontChoice(id: 'cairo', name: 'Cairo', family: 'Cairo'),
];

/// Per-profile appearance/UI preferences — theme mode (light/dark/system),
/// the accent color preset, the UI font, grid density, and language. Each
/// user [Profile] has its own isolated set, so switching profiles re-themes
/// (and can re-localize) the whole app. This is the place future per-profile
/// settings should go rather than scattering prefs keys across screens.
///
/// Keys are suffixed with the profile id ([_k]). [loadFor] is called at
/// startup for the active profile and again on every profile switch; unlike a
/// one-shot loader it re-reads each time so the in-memory state always matches
/// the active profile.
class SettingsService extends ChangeNotifier {
  SettingsService._();
  static final SettingsService instance = SettingsService._();

  /// The profile whose settings are currently loaded. Set by [loadFor].
  String? _profileId;

  /// Prefixes a base key with the active profile id, isolating each profile's
  /// settings from the others.
  String _k(String base) => '${base}_$_profileId';

  ThemeMode _themeMode = ThemeMode.dark;
  ThemeMode get themeMode => _themeMode;

  ThemePreset _themePreset = kThemePresets.first;
  ThemePreset get themePreset => _themePreset;

  FontChoice _fontChoice = kFontChoices.first;
  FontChoice get fontChoice => _fontChoice;

  /// The family to hand to ThemeData - null for the system default.
  String? get fontFamily => _fontChoice.family;

  GridDensity _gridDensity = GridDensity.comfortable;
  GridDensity get gridDensity => _gridDensity;

  /// Convenience: the ideal poster-tile width for the current density.
  double get gridIdealTileWidth => gridIdealTileWidthOf(_gridDensity);

  AppLanguage _language = AppLanguage.system;
  AppLanguage get language => _language;

  /// The locale to hand to MaterialApp - null lets it follow the device.
  Locale? get appLocale => appLanguageLocale(_language);

  /// Whether the optional enhanced-search crawl is on (indexes each movie's/
  /// series' cast/director/genre so Search and the browse filters can match
  /// them, not just titles). Off by default — it's request-heavy against the
  /// provider; see the Settings tile's explanation. Per-profile like the rest.
  bool _enhancedSearchEnabled = false;
  bool get enhancedSearchEnabled => _enhancedSearchEnabled;

  /// Roll on to the next episode when one finishes. Season-bounded: a season
  /// finale never pulls you into the next season - see EpisodeNavigator.
  bool _autoplayNextEpisode = true;
  bool get autoplayNextEpisode => _autoplayNextEpisode;

  /// Player volume, 0-100. Persisted because it is a property of the room you
  /// are sitting in, not of the video: having it snap back to full on every
  /// new episode is exactly the wrong default at night.
  double _playerVolume = 100;
  double get playerVolume => _playerVolume;

  /// When on (and [externalPlayerPath] is set), playback is handed off to an
  /// external player (VLC on Windows for now) instead of the built-in one.
  /// Off by default. Per-profile like the rest — the path is device-ish, but
  /// keeping it in the profile-scoped store keeps the service uniform.
  bool _externalPlayerEnabled = false;
  bool get externalPlayerEnabled => _externalPlayerEnabled;

  /// Absolute path to the external player executable (e.g. vlc.exe). Empty when
  /// unset — in which case external playback stays off regardless of the flag.
  String _externalPlayerPath = '';
  String get externalPlayerPath => _externalPlayerPath;

  /// The single source of truth for "should this stream open externally?":
  /// the flag is on AND a path is configured.
  bool get useExternalPlayer =>
      _externalPlayerEnabled && _externalPlayerPath.isNotEmpty;

  /// Loads (or reloads) settings for [profileId]. Called at startup for the
  /// active profile — before runApp(), so the first frame already reflects
  /// the saved theme instead of flashing the default — and again on every
  /// profile switch so the app re-themes/re-localizes in place.
  Future<void> loadFor(String profileId) async {
    _profileId = profileId;
    final prefs = await SharedPreferences.getInstance();

    // Pre-profiles builds wrote these keys unprefixed. The upgrade migration
    // moves them into the default profile's scope, but fall back to the legacy
    // key for the default profile in case settings are read before migration.
    String? read(String base) =>
        prefs.getString(_k(base)) ??
        (profileId == defaultSettingsProfileId ? prefs.getString(base) : null);

    final savedMode = read(_themeModePrefsKey);
    _themeMode = ThemeMode.values.firstWhere(
      (m) => m.name == savedMode,
      orElse: () => ThemeMode.dark,
    );
    final savedPreset = read(_themePresetPrefsKey);
    _themePreset = kThemePresets.firstWhere(
      (p) => p.id == savedPreset,
      orElse: () => kThemePresets.first,
    );
    final savedFont = read(_fontPrefsKey);
    _fontChoice = kFontChoices.firstWhere(
      (f) => f.id == savedFont,
      orElse: () => kFontChoices.first,
    );
    final savedDensity = read(_gridDensityPrefsKey);
    _gridDensity = GridDensity.values.firstWhere(
      (d) => d.name == savedDensity,
      orElse: () => GridDensity.comfortable,
    );
    final savedLanguage = read(_languagePrefsKey);
    _language = AppLanguage.values.firstWhere(
      (l) => l.name == savedLanguage,
      orElse: () => AppLanguage.system,
    );
    _playerVolume =
        (prefs.getDouble(_k(_playerVolumePrefsKey)) ?? 100).clamp(0, 100);
    _autoplayNextEpisode =
        prefs.getBool(_k(_autoplayNextEpisodePrefsKey)) ?? true;
    _enhancedSearchEnabled =
        prefs.getBool(_k(_enhancedSearchPrefsKey)) ?? false;
    _externalPlayerEnabled =
        prefs.getBool(_k(_externalPlayerEnabledPrefsKey)) ?? false;
    _externalPlayerPath = prefs.getString(_k(_externalPlayerPathPrefsKey)) ?? '';
    notifyListeners();
  }

  /// Wipes a removed profile's saved settings from disk. Part of the
  /// delete-profile cascade.
  Future<void> deleteFor(String profileId) async {
    final prev = _profileId;
    _profileId = profileId;
    final prefs = await SharedPreferences.getInstance();
    for (final base in const [
      _themeModePrefsKey,
      _themePresetPrefsKey,
      _fontPrefsKey,
      _gridDensityPrefsKey,
      _languagePrefsKey,
      _enhancedSearchPrefsKey,
      _autoplayNextEpisodePrefsKey,
      _playerVolumePrefsKey,
      _externalPlayerEnabledPrefsKey,
      _externalPlayerPathPrefsKey,
    ]) {
      await prefs.remove(_k(base));
    }
    _profileId = prev;
  }

  @visibleForTesting
  void resetForTesting() {
    _profileId = null;
    _themeMode = ThemeMode.dark;
    _themePreset = kThemePresets.first;
    _fontChoice = kFontChoices.first;
    _gridDensity = GridDensity.comfortable;
    _language = AppLanguage.system;
    _enhancedSearchEnabled = false;
    _autoplayNextEpisode = true;
    _playerVolume = 100;
    _externalPlayerEnabled = false;
    _externalPlayerPath = '';
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == _themeMode) return;
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_k(_themeModePrefsKey), mode.name);
  }

  Future<void> setThemePreset(ThemePreset preset) async {
    if (preset.id == _themePreset.id) return;
    _themePreset = preset;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_k(_themePresetPrefsKey), preset.id);
  }

  Future<void> setFontChoice(FontChoice choice) async {
    if (choice.id == _fontChoice.id) return;
    _fontChoice = choice;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_k(_fontPrefsKey), choice.id);
  }

  Future<void> setGridDensity(GridDensity density) async {
    if (density == _gridDensity) return;
    _gridDensity = density;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_k(_gridDensityPrefsKey), density.name);
  }

  Future<void> setLanguage(AppLanguage language) async {
    if (language == _language) return;
    _language = language;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_k(_languagePrefsKey), language.name);
  }

  /// Not notifyListeners()-ing: the player already holds the live value and
  /// rebuilding every listener on each drag of a volume slider would be a lot
  /// of churn for a number nothing else on screen displays.
  Future<void> setPlayerVolume(double volume) async {
    final clamped = volume.clamp(0.0, 100.0);
    if (clamped == _playerVolume) return;
    _playerVolume = clamped;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_k(_playerVolumePrefsKey), clamped);
  }

  Future<void> setAutoplayNextEpisode(bool enabled) async {
    if (enabled == _autoplayNextEpisode) return;
    _autoplayNextEpisode = enabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_k(_autoplayNextEpisodePrefsKey), enabled);
  }

  Future<void> setEnhancedSearchEnabled(bool enabled) async {
    if (enabled == _enhancedSearchEnabled) return;
    _enhancedSearchEnabled = enabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_k(_enhancedSearchPrefsKey), enabled);
  }

  Future<void> setExternalPlayerEnabled(bool enabled) async {
    if (enabled == _externalPlayerEnabled) return;
    _externalPlayerEnabled = enabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_k(_externalPlayerEnabledPrefsKey), enabled);
  }

  Future<void> setExternalPlayerPath(String path) async {
    if (path == _externalPlayerPath) return;
    _externalPlayerPath = path;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_k(_externalPlayerPathPrefsKey), path);
  }
}
