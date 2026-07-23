/// The app's display name. Change it here and every user-facing reference -
/// the window title, error messages, the suggested export filename - updates
/// with it.
///
/// Stable code identifiers deliberately do NOT derive from this: the Dart
/// package name (`iptv_player`), the `IptvPlayerApp` widget, and the settings
/// export format marker (`SettingsBackup.formatMarker`) stay fixed so a
/// rename never breaks imports or the build. Likewise, "IPTV" used as a
/// technology term (e.g. "IPTV subscription") is domain language, not the
/// app's name, and isn't sourced from here.
const appName = 'IPTV Player';

/// A filesystem-safe, lowercase slug of [appName] - used where the name
/// needs to appear as an identifier-ish string (e.g. the suggested export
/// filename) so those track the display name too. 'IPTV Player' -> 'iptv_player'.
String get appSlug => appName
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
    .replaceAll(RegExp(r'^_+|_+$'), '');
