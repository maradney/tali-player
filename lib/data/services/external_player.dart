import 'dart:io';

/// Launches streams in an external media player (VLC on Windows for now).
/// Kept tiny and dependency-free — it just shells out to the configured
/// executable with the stream URL as its argument.
///
/// This is the escape hatch for codecs/containers the built-in media_kit
/// player can't handle; the user opts in and points it at their player in
/// Settings. Expanding to other platforms/players (see the roadmap) means
/// adding candidates + a per-platform notion of "supported".
class ExternalPlayer {
  ExternalPlayer._();

  /// External playback is currently wired for Windows only.
  static bool get isSupported => Platform.isWindows;

  /// Common VLC install locations on Windows, in the order we'd trust them.
  /// Pure (no filesystem access) so it's unit-testable; [detectDefaultPath]
  /// is what actually probes disk.
  static List<String> windowsVlcCandidates() {
    final programFiles =
        Platform.environment['ProgramFiles'] ?? r'C:\Program Files';
    final programFilesX86 =
        Platform.environment['ProgramFiles(x86)'] ?? r'C:\Program Files (x86)';
    return [
      '$programFiles\\VideoLAN\\VLC\\vlc.exe',
      '$programFilesX86\\VideoLAN\\VLC\\vlc.exe',
    ];
  }

  /// The first VLC executable that actually exists on disk, or null if none of
  /// the standard locations have it (the user can still browse to a custom one).
  static Future<String?> detectDefaultPath() async {
    if (!isSupported) return null;
    for (final candidate in windowsVlcCandidates()) {
      if (await File(candidate).exists()) return candidate;
    }
    return null;
  }

  /// Launches [url] in the player at [executablePath], detached so it keeps
  /// running independently of this app. Returns false (rather than throwing)
  /// if the process can't be started — e.g. a stale/incorrect path — so the
  /// caller can show a friendly "couldn't open" message.
  static Future<bool> launch(String executablePath, String url) async {
    try {
      await Process.start(
        executablePath,
        [url],
        mode: ProcessStartMode.detached,
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}
