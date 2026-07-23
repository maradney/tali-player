import 'dart:convert';

import 'package:flutter/material.dart';

import '../../app_info.dart';
import '../models/account.dart';
import 'accounts_service.dart';
import 'favorites_service.dart';
import 'home_strips_service.dart';
import 'kids_filter_service.dart';
import 'playback_service.dart';
import 'profiles_service.dart';
import 'settings_service.dart';
import 'watch_history_service.dart';
import 'watchlist_service.dart';

/// Thrown when an import file isn't a valid settings backup from this app.
/// Carries a user-facing [message] the UI can show directly.
class SettingsBackupException implements Exception {
  final String message;
  SettingsBackupException(this.message);
  @override
  String toString() => message;
}

/// Outcome of a successful import, so the UI can report what changed.
class SettingsImportResult {
  final int accountsImported;
  final bool appearanceImported;

  const SettingsImportResult({
    required this.accountsImported,
    required this.appearanceImported,
  });
}

/// Serializes and restores the user's portable settings - saved playlists
/// (accounts) and appearance (theme mode, color scheme, font) - as a JSON
/// document. Deliberately excludes anything that shouldn't travel:
///   - the parental-control PIN (a security control, not a preference), and
///   - all cache/derived data (search index, image/EPG/detail caches),
///     which is regenerable and account-specific.
///
/// This layer only does JSON <-> app-state; picking/reading/writing the
/// actual file is left to the UI so this stays pure and unit-testable.
class SettingsBackup {
  SettingsBackup._();

  /// Reads a credential field as a non-empty String without ever throwing.
  /// Only genuine strings count; anything else (number, bool, list, map,
  /// null, empty) is treated as absent so the caller skips that entry - a
  /// numeric or structured credential is corrupt, not something to salvage,
  /// and our own exports always write plain strings.
  static String? _asNonEmptyString(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return value;
  }

  /// Marker + version so [import] can reject unrelated JSON and so the
  /// format can evolve without silently mis-reading old files. This is a
  /// fixed compatibility anchor - do NOT tie it to the app's display name
  /// ([appName]), or renaming the app would make every prior export
  /// unreadable.
  static const formatMarker = 'iptv_player_settings';
  static const formatVersion = 1;

  /// The active profile's accounts (with their favorites, watch history, and
  /// continue-watching positions) plus appearance, as a pretty-printed JSON
  /// string.
  ///
  /// NOTE: this includes each playlist's password in readable form - it has
  /// to, or an imported account couldn't authenticate. Callers must warn the
  /// user that the resulting file is sensitive before writing it anywhere.
  static Future<String> export() async {
    final settings = SettingsService.instance;
    final accounts = <Map<String, dynamic>>[];
    for (final a in AccountsService.instance.accounts) {
      accounts.add({
        'name': a.name,
        // Distinguishes an M3U playlist (below) from an Xtream login. Absent on
        // pre-M3U exports → treated as Xtream on import.
        'sourceKind': a.sourceKind.name,
        'serverUrl': a.serverUrl,
        'username': a.username,
        'password': a.password,
        'm3uUrl': a.m3uUrl,
        'epgUrl': a.epgUrl,
        // Per-playlist user data (not cache/derived): restored on import.
        'favorites': await FavoritesService.instance.exportFor(a),
        'watchlist': await WatchlistService.instance.exportFor(a),
        'watchHistory': await WatchHistoryService.instance.exportFor(a),
        'continueWatching': await PlaybackService.instance.exportFor(a),
        'homeStrips': await HomeStripsService.instance.exportFor(a),
        'kidsFilter': await KidsFilterService.instance.exportFor(a),
      });
    }
    return const JsonEncoder.withIndent('  ').convert({
      'format': formatMarker,
      'version': formatVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      '_note': 'Contains playlist passwords in readable form - keep this '
          'file private.',
      'accounts': accounts,
      'appearance': {
        'themeMode': settings.themeMode.name,
        'themePreset': settings.themePreset.id,
        'font': settings.fontChoice.id,
      },
    });
  }

  /// Parses [jsonString] and applies it: accounts are merged in (an existing
  /// playlist with the same server+username is updated in place, nothing is
  /// removed), and any recognized appearance values are set. Unknown values
  /// are ignored rather than rejected, so a newer export stays partially
  /// importable in an older build.
  ///
  /// Throws [SettingsBackupException] if the input isn't JSON or isn't a
  /// settings file produced by this app.
  static Future<SettingsImportResult> import(String jsonString) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(jsonString);
    } catch (_) {
      throw SettingsBackupException("This file isn't valid JSON.");
    }
    if (decoded is! Map || decoded['format'] != formatMarker) {
      throw SettingsBackupException(
        "This doesn't look like a $appName settings file.",
      );
    }

    var accountsImported = 0;
    final accounts = decoded['accounts'];
    if (accounts is List) {
      for (final raw in accounts) {
        if (raw is! Map) continue;
        // Coerce defensively (never `as String`) so a wrong-typed field skips
        // the entry like a missing one instead of throwing - a hand-edited or
        // foreign file shouldn't be able to abort the whole import midway.
        final name = _asNonEmptyString(raw['name']);
        // Imported playlists join the profile the user is importing into.
        final profileId = ProfilesService.instance.activeProfileId ??
            Account.defaultProfileId;

        final Account account;
        if (raw['sourceKind'] == AccountSourceKind.m3u.name) {
          final url = _asNonEmptyString(raw['m3uUrl']);
          if (url == null) continue; // the playlist URL is the M3U minimum
          account = Account.m3u(
            profileId: profileId,
            name: name ?? url,
            url: url,
            epgUrl: _asNonEmptyString(raw['epgUrl']),
          );
        } else {
          final serverUrl = _asNonEmptyString(raw['serverUrl']);
          final username = _asNonEmptyString(raw['username']);
          final password = _asNonEmptyString(raw['password']);
          // server+username+password are the minimum to make a usable account.
          if (serverUrl == null || username == null || password == null) {
            continue;
          }
          account = Account(
            profileId: profileId,
            name: name ?? serverUrl,
            serverUrl: serverUrl,
            username: username,
            password: password,
          );
        }
        await AccountsService.instance.addAccount(account);
        accountsImported++;

        // Restore this playlist's favorites / history / resume positions, if
        // present. Missing sections (older backups) are simply skipped.
        final favorites = raw['favorites'];
        if (favorites is List) {
          await FavoritesService.instance.importFor(account, favorites);
        }
        final watchlist = raw['watchlist'];
        if (watchlist is List) {
          await WatchlistService.instance.importFor(account, watchlist);
        }
        final history = raw['watchHistory'];
        if (history is List) {
          await WatchHistoryService.instance.importFor(account, history);
        }
        final resume = raw['continueWatching'];
        if (resume is List) {
          await PlaybackService.instance.importFor(account, resume);
        }
        final homeStrips = raw['homeStrips'];
        if (homeStrips is List) {
          await HomeStripsService.instance.importFor(account, homeStrips);
        }
        final kidsFilter = raw['kidsFilter'];
        if (kidsFilter is Map) {
          await KidsFilterService.instance
              .importFor(account, kidsFilter.cast<String, dynamic>());
        }
      }
    }

    var appearanceImported = false;
    final appearance = decoded['appearance'];
    if (appearance is Map) {
      final mode = ThemeMode.values
          .where((m) => m.name == appearance['themeMode']);
      if (mode.isNotEmpty) {
        await SettingsService.instance.setThemeMode(mode.first);
      }
      final preset =
          kThemePresets.where((p) => p.id == appearance['themePreset']);
      if (preset.isNotEmpty) {
        await SettingsService.instance.setThemePreset(preset.first);
      }
      final font = kFontChoices.where((f) => f.id == appearance['font']);
      if (font.isNotEmpty) {
        await SettingsService.instance.setFontChoice(font.first);
      }
      appearanceImported = true;
    }

    return SettingsImportResult(
      accountsImported: accountsImported,
      appearanceImported: appearanceImported,
    );
  }
}
