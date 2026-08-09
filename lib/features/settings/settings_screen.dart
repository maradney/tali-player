import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path/path.dart' as p;

import '../../app_info.dart';
import '../../platform_capabilities.dart';
import '../../data/api/xtream_api_service.dart';
import '../../data/db/catalog_database.dart';
import '../../data/models/account.dart';
import '../../data/models/catalog_row.dart';
import '../../data/services/catalog_enrichment_service.dart';
import '../../data/services/catalog_sync_service.dart';
import '../../data/services/external_player.dart';
import '../../data/services/pin_lock_service.dart';
import '../../data/services/settings_backup.dart';
import '../../data/services/settings_service.dart';
import '../../data/services/tray_service.dart';
import '../../l10n/app_localizations.dart';
import '../accounts/accounts_screen.dart';
import '../common/disclaimer_dialog.dart';
import '../common/pin_dialogs.dart';
import '../common/poster_cache_repair.dart';
import '../downloads/downloads_screen.dart';
import 'account_status_card.dart';
import 'diagnostics_screen.dart';

const _backupTypeGroup = XTypeGroup(label: 'JSON', extensions: ['json']);

/// Name of the settings-backup file: the suggested name in the desktop save
/// dialog, and the actual name where we pick it ourselves (Android, which has
/// no save dialog). Tracks [appSlug] so renaming the app renames the file.
String get backupFileName => '${appSlug}_settings.json';

/// [backupFileName] inside [directory] — where the export lands on platforms
/// that can only hand us a folder. Separate from the picking so the naming can
/// be tested without a file dialog.
String backupPathIn(String directory) => p.join(directory, backupFileName);

/// Settings, grouped into a few basic categories. Anything account-specific
/// (add/remove/switch playlist) already lives in AccountsScreen and is
/// linked from here rather than duplicated.
class SettingsScreen extends StatelessWidget {
  final Account account;

  const SettingsScreen({super.key, required this.account});

  Future<void> _clearImageCache(BuildContext context) async {
    final l = AppLocalizations.of(context)!;
    await DefaultCacheManager().emptyCache();
    // Nothing is cached any more, so the one-repair-per-URL guard has nothing
    // left to protect against - without this, a poster already repaired this
    // session would never be retried again.
    PosterCacheRepair.instance.forgetAll();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.imageCacheCleared)),
    );
  }

  Future<void> _rebuildSearchIndex(BuildContext context) async {
    final l = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l.rebuildIndexTitle),
        content: Text(l.rebuildIndexBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.rebuild),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await CatalogDatabase.instance
        .deleteForAccount(CatalogRow.accountKeyFor(account));
    if (!context.mounted) return;
    unawaited(
      CatalogSyncService.instance.fullSync(account, XtreamApiService()),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.rebuildingIndex)),
    );
  }

  Future<void> _exportSettings(BuildContext context) async {
    final l = AppLocalizations.of(context)!;
    // The file holds playlist passwords in readable form (they normally live
    // in OS-encrypted storage) - make that explicit before writing it out.
    final proceed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l.exportTitle),
        content: Text(l.exportBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            // Names what actually opens next: a save dialog where there is
            // one, and a folder picker on Android, where the file is named for
            // the user. Saying "file" there sent people looking for a filename
            // field that never appears.
            child: Text(
                supportsSaveFileDialog ? l.chooseFile : l.chooseFolder),
          ),
        ],
      ),
    );
    if (proceed != true) return;

    final String? destination;
    if (supportsSaveFileDialog) {
      final location = await getSaveLocation(
        suggestedName: backupFileName,
        acceptedTypeGroups: const [_backupTypeGroup],
      );
      destination = location?.path;
    } else {
      // Android has no save dialog (file_selector_android implements only
      // openFile/openFiles/getDirectoryPath), so ask for a folder and name the
      // file ourselves instead of letting getSaveLocation throw.
      final directory = await getDirectoryPath();
      destination = directory == null ? null : backupPathIn(directory);
    }
    if (destination == null) return; // user cancelled the picker

    try {
      await File(destination).writeAsString(await SettingsBackup.export());
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.couldNotWriteFile('$e'))),
      );
      return;
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.settingsExported)),
    );
  }

  Future<void> _importSettings(BuildContext context) async {
    final l = AppLocalizations.of(context)!;
    final file = await openFile(acceptedTypeGroups: const [_backupTypeGroup]);
    if (file == null) return; // cancelled

    String content;
    try {
      content = await file.readAsString();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.couldNotReadFile('$e'))),
      );
      return;
    }

    try {
      final result = await SettingsBackup.import(content);
      if (!context.mounted) return;
      final parts = <String>[
        if (result.accountsImported > 0)
          l.playlistCount(result.accountsImported),
        if (result.appearanceImported) l.appearanceSettings,
      ];
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            parts.isEmpty
                ? l.nothingToImport
                : l.importedItems(parts.join(' ${l.and} ')),
          ),
        ),
      );
    } on SettingsBackupException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (_) {
      // Belt-and-braces: import shouldn't throw anything but a
      // SettingsBackupException, but never let an unexpected error fail
      // silently with no feedback to the user.
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.importCorrupted)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l.settingsTitle)),
      body: AnimatedBuilder(
        animation: Listenable.merge([SettingsService.instance, PinLockService.instance]),
        builder: (context, _) {
          final themeMode = SettingsService.instance.themeMode;
          final hasPin = PinLockService.instance.hasPin;
          return ListView(
            children: [
              _SectionHeader(l.settingsAccount),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: AccountStatusCard(
                  // Rebuild the card (re-fetch) if the active account changes
                  // while Settings is open.
                  key: ValueKey(account.key),
                  account: account,
                ),
              ),
              _SectionHeader(l.settingsPlaylists),
              ListTile(
                leading: const Icon(Icons.playlist_play),
                title: Text(l.settingsManagePlaylists),
                subtitle: Text(l.settingsManagePlaylistsSubtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AccountsScreen()),
                ),
              ),
              const Divider(),
              _SectionHeader(l.settingsAppearance),
              ListTile(
                leading: const Icon(Icons.language),
                title: Text(l.settingsLanguage),
                trailing: DropdownButton<AppLanguage>(
                  value: SettingsService.instance.language,
                  onChanged: (lang) {
                    if (lang != null) {
                      SettingsService.instance.setLanguage(lang);
                    }
                  },
                  items: [
                    for (final lang in AppLanguage.values)
                      DropdownMenuItem(
                        value: lang,
                        child: Text(lang == AppLanguage.system
                            ? l.languageSystem
                            : languageEndonym(lang)),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: l.settingsFont,
                    border: const OutlineInputBorder(),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: SettingsService.instance.fontChoice.id,
                      isExpanded: true,
                      isDense: true,
                      // Each option previews in its own typeface, like Slack.
                      items: [
                        for (final choice in kFontChoices)
                          DropdownMenuItem(
                            value: choice.id,
                            child: Text(
                              // 'System default' is the one non-proper-noun
                              // name; reuse the language picker's label.
                              choice.family == null
                                  ? l.languageSystem
                                  : choice.name,
                              style: TextStyle(fontFamily: choice.family),
                            ),
                          ),
                      ],
                      onChanged: (id) {
                        if (id == null) return;
                        SettingsService.instance.setFontChoice(
                          kFontChoices.firstWhere((f) => f.id == id),
                        );
                      },
                    ),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.brightness_6_outlined),
                title: Text(l.settingsTheme),
                subtitle: Text(_themeModeLabel(themeMode, l)),
                trailing: SegmentedButton<ThemeMode>(
                  segments: [
                    ButtonSegment(
                      value: ThemeMode.system,
                      icon: const Icon(Icons.brightness_auto),
                      tooltip: l.system,
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      icon: const Icon(Icons.light_mode),
                      tooltip: l.themeLight,
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      icon: const Icon(Icons.dark_mode),
                      tooltip: l.themeDark,
                    ),
                  ],
                  selected: {themeMode},
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) =>
                      SettingsService.instance.setThemeMode(selection.first),
                ),
              ),
              _SectionHeader(l.settingsColorScheme),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Wrap(
                  spacing: 14,
                  runSpacing: 12,
                  children: [
                    for (final preset in kThemePresets)
                      _ThemeSwatch(
                        preset: preset,
                        selected: preset.id ==
                            SettingsService.instance.themePreset.id,
                        onTap: () =>
                            SettingsService.instance.setThemePreset(preset),
                      ),
                  ],
                ),
              ),
              const Divider(),
              _SectionHeader(l.settingsParentalControls),
              ListTile(
                leading: Icon(hasPin ? Icons.lock : Icons.lock_open),
                title: Text(hasPin ? l.settingsChangePin : l.settingsSetPin),
                subtitle: Text(l.pinLockHint),
                onTap: () => showSetOrChangePinDialog(context),
              ),
              if (hasPin)
                ListTile(
                  leading: const Icon(Icons.lock_reset),
                  title: Text(l.settingsRemovePin),
                  subtitle: Text(l.removePinSubtitle),
                  onTap: () => showRemovePinDialog(context),
                ),
              const Divider(),
              _SectionHeader(l.settingsDataStorage),
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: Text(l.downloadsTitle),
                subtitle: Text(l.downloadsSubtitle),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DownloadsScreen(account: account),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.image_outlined),
                title: Text(l.settingsClearImageCache),
                subtitle: Text(l.clearImageCacheSubtitle),
                onTap: () => _clearImageCache(context),
              ),
              ListTile(
                leading: const Icon(Icons.refresh),
                title: Text(l.settingsRebuildIndex),
                subtitle: Text(l.forPlaylistOnly(account.name)),
                onTap: () => _rebuildSearchIndex(context),
              ),
              _EnhancedSearchTile(account: account),
              if (ExternalPlayer.isSupported || Platform.isWindows) ...[
                const Divider(),
                _SectionHeader(l.settingsPlayback),
                if (ExternalPlayer.isSupported) const _ExternalPlayerTile(),
                if (Platform.isWindows) const _TrayModeTile(),
              ],
              const Divider(),
              _SectionHeader(l.settingsBackup),
              ListTile(
                leading: const Icon(Icons.upload_file_outlined),
                title: Text(l.settingsExport),
                subtitle: Text(l.exportSubtitle),
                onTap: () => _exportSettings(context),
              ),
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: Text(l.settingsImport),
                subtitle: Text(l.importSubtitle),
                onTap: () => _importSettings(context),
              ),
              const Divider(),
              _SectionHeader(l.settingsAbout),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(l.settingsAboutThisApp),
                onTap: () => showDisclaimerDialog(context),
              ),
              ListTile(
                leading: const Icon(Icons.build_outlined),
                title: Text(l.diagnosticsTitle),
                subtitle: Text(l.diagnosticsSubtitle),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DiagnosticsScreen(account: account),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static String _themeModeLabel(ThemeMode mode, AppLocalizations l) {
    switch (mode) {
      case ThemeMode.system:
        return l.themeSystem;
      case ThemeMode.light:
        return l.themeLight;
      case ThemeMode.dark:
        return l.themeDark;
    }
  }
}

/// A tappable preview of one accent preset: a gradient circle that blends
/// the accent (the seed itself) into the complementary hue Material derives
/// from it, so the swatch hints at the palette the theme produces - like
/// Slack's theme circles. The selected one is ringed and check-marked.
class _ThemeSwatch extends StatelessWidget {
  final ThemePreset preset;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeSwatch({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Preview at a fixed light brightness so the swatch stays vivid on the
    // dark settings panel (dark-mode primaries are intentionally pastel and
    // would look washed out here) - this is a hint, not an exact render.
    final scheme = ColorScheme.fromSeed(
      seedColor: preset.seed,
      brightness: Brightness.light,
    );
    final ringColor = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [preset.seed, scheme.secondary, scheme.tertiary],
              ),
              border: Border.all(
                color: selected ? ringColor : Theme.of(context).dividerColor,
                width: selected ? 3 : 1,
              ),
            ),
            child: selected
                ? const Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(2),
                        child:
                            Icon(Icons.check, color: Colors.white, size: 16),
                      ),
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 68,
            child: Text(
              preset.name,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The external-player control: a switch to route playback to VLC, plus a
/// configured-path row with "Detect VLC" and "Browse…" when it's on. Only
/// added to the tree on supported platforms (Windows for now).
/// Windows-only: closing the window hides the app to the system tray instead
/// of exiting (playback/downloads keep running); the tray icon restores it.
class _TrayModeTile extends StatelessWidget {
  const _TrayModeTile();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AnimatedBuilder(
      animation: TrayService.instance,
      builder: (context, _) => SwitchListTile(
        secondary: const Icon(Icons.minimize),
        title: Text(l.settingsCloseToTray),
        subtitle: Text(l.settingsCloseToTraySubtitle),
        value: TrayService.instance.closeToTray,
        onChanged: (v) => TrayService.instance
            .setCloseToTray(v, locale: Localizations.localeOf(context)),
      ),
    );
  }
}

class _ExternalPlayerTile extends StatelessWidget {
  const _ExternalPlayerTile();

  Future<void> _browse(BuildContext context) async {
    const group = XTypeGroup(label: 'Executable', extensions: ['exe']);
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file != null) {
      await SettingsService.instance.setExternalPlayerPath(file.path);
    }
  }

  Future<void> _detect(BuildContext context) async {
    final l = AppLocalizations.of(context)!;
    final path = await ExternalPlayer.detectDefaultPath();
    if (path != null) {
      await SettingsService.instance.setExternalPlayerPath(path);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.externalPlayerNotFound)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AnimatedBuilder(
      animation: SettingsService.instance,
      builder: (context, _) {
        final enabled = SettingsService.instance.externalPlayerEnabled;
        final path = SettingsService.instance.externalPlayerPath;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              secondary: const Icon(Icons.open_in_new),
              title: Text(l.externalPlayerTitle),
              subtitle: Text(l.externalPlayerSubtitle),
              value: enabled,
              onChanged: (v) =>
                  SettingsService.instance.setExternalPlayerEnabled(v),
            ),
            if (enabled)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.externalPlayerExplainer,
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 8),
                    Text(
                      path.isEmpty ? l.externalPlayerPathNotSet : path,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontStyle:
                                path.isEmpty ? FontStyle.italic : FontStyle.normal,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => _detect(context),
                          icon: const Icon(Icons.search),
                          label: Text(l.externalPlayerDetect),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _browse(context),
                          icon: const Icon(Icons.folder_open),
                          label: Text(l.externalPlayerBrowse),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The opt-in "enhanced search" control: a switch, a plain-language
/// explanation of what it does and its cost, a live progress line, and a
/// Rebuild action. Listens to both [SettingsService] (the flag) and
/// [CatalogEnrichmentService] (progress) so it updates as the crawl advances.
class _EnhancedSearchTile extends StatelessWidget {
  final Account account;

  const _EnhancedSearchTile({required this.account});

  Future<void> _toggle(bool value) async {
    await SettingsService.instance.setEnhancedSearchEnabled(value);
    // Turning it on kicks the crawl off immediately; turning it off just lets
    // any in-flight crawl notice the flag and stop.
    if (value) {
      unawaited(CatalogEnrichmentService.instance
          .enrichIfEnabled(account, XtreamApiService()));
    }
  }

  void _rebuild(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    unawaited(CatalogEnrichmentService.instance
        .rebuild(account, XtreamApiService()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.enhancedSearchRebuildStarted)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: Listenable.merge(
          [SettingsService.instance, CatalogEnrichmentService.instance]),
      builder: (context, _) {
        final enabled = SettingsService.instance.enhancedSearchEnabled;
        final progress = CatalogEnrichmentService.instance.progressFor(account);
        final running = CatalogEnrichmentService.instance.isEnriching(account);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              secondary: const Icon(Icons.person_search_outlined),
              title: Text(l.enhancedSearchTitle),
              subtitle: Text(l.enhancedSearchSubtitle),
              value: enabled,
              onChanged: (v) => _toggle(v),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
              child: Text(
                l.enhancedSearchExplainer,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (enabled)
              Padding(
                padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
                child: _EnhancedSearchStatus(
                  progress: progress,
                  running: running,
                  onRebuild: running ? null : () => _rebuild(context),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The progress line + Rebuild button shown under the switch when enhanced
/// search is on. Kept separate so the tile's build stays readable.
class _EnhancedSearchStatus extends StatelessWidget {
  final ({int enriched, int total})? progress;
  final bool running;
  final VoidCallback? onRebuild;

  const _EnhancedSearchStatus({
    required this.progress,
    required this.running,
    required this.onRebuild,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final total = progress?.total ?? 0;
    final done = progress?.enriched ?? 0;
    final complete = total > 0 && done >= total;

    final String status;
    if (total == 0) {
      status = l.enhancedSearchNeedsIndex;
    } else if (complete && !running) {
      status = l.enhancedSearchComplete;
    } else {
      status = l.enhancedSearchProgress(done, total);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (total > 0 && !complete)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: LinearProgressIndicator(value: done / total),
          ),
        Row(
          children: [
            if (running) ...[
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(child: Text(status)),
            TextButton.icon(
              onPressed: onRebuild,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(l.rebuild),
            ),
          ],
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;

  const _SectionHeader(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .labelLarge
            ?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}
