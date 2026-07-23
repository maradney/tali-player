import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app_info.dart';
import 'l10n/app_localizations.dart';
import 'platform_capabilities.dart';
import 'font_licenses.dart';
import 'data/services/accounts_service.dart';
import 'data/services/channel_preferences_service.dart';
import 'data/services/download_service.dart';
import 'data/services/favorites_service.dart';
import 'data/services/home_strips_service.dart';
import 'data/services/kids_filter_service.dart';
import 'data/services/pin_lock_service.dart';
import 'data/services/playback_service.dart';
import 'data/services/profiles_migration.dart';
import 'data/services/profiles_service.dart';
import 'data/services/settings_service.dart';
import 'data/services/tray_service.dart';
import 'data/services/watch_history_service.dart';
import 'data/services/watchlist_service.dart';
import 'features/auth/login_screen.dart';
import 'features/common/disclaimer_dialog.dart';
import 'features/home/home_shell.dart';
import 'features/profiles/profile_picker_screen.dart';

void main() async {
  // Needed since we await service loading before runApp().
  WidgetsFlutterBinding.ensureInitialized();

  // Surface the bundled fonts' OFL licenses in the About > Licenses page.
  registerFontLicenses();

  // Must be called before runApp() - initializes the native libmpv
  // bindings for whichever platform you're running on.
  MediaKit.ensureInitialized();

  // Window/tray management is desktop-only (window_manager and tray_manager
  // have no mobile implementations — unguarded calls throw on Android/iOS).
  if (isDesktopWindow) {
    // Needed before any windowManager calls (the player screen's fullscreen
    // toggle).
    await windowManager.ensureInitialized();
    // Drive the OS window title from the same constant as everything else, so
    // renaming the app updates the title bar too (not just Flutter-drawn text).
    await windowManager.setTitle(appName);
    // Keep the window from being shrunk below a usable size. The default size
    // itself is set in the native runner (windows/runner/main.cpp).
    await windowManager.setMinimumSize(const Size(900, 640));
    // System-tray mode ("keep running in the tray on close") — no-op unless
    // the user enabled it in Settings. Internally Windows-only.
    await TrayService.instance.init();
  }

  // Fold any pre-profiles install into the profiles model first (re-keys
  // existing playlists/data into the default profile), then load profiles so
  // the active profile is known before anything scoped to it loads.
  await ProfilesMigration.runIfNeeded();
  await ProfilesService.instance.load();
  final activeProfileId = ProfilesService.instance.activeProfileId!;

  // Load saved playlists so we know whether to land on Login or straight
  // into HomeShell, and load the active profile's settings + the active
  // playlist's data - all ready by the time the first frame needs them.
  await SettingsService.instance.loadFor(activeProfileId);
  await AccountsService.instance.load();
  final activeAccount = AccountsService.instance.activeAccount;
  if (activeAccount != null) {
    await FavoritesService.instance.loadFor(activeAccount);
    await WatchlistService.instance.loadFor(activeAccount);
    await DownloadService.instance.loadFor(activeAccount);
    await PlaybackService.instance.loadFor(activeAccount);
    await WatchHistoryService.instance.loadFor(activeAccount);
    await PinLockService.instance.loadFor(activeAccount);
    await KidsFilterService.instance.loadFor(activeAccount);
    await ChannelPreferencesService.instance.loadFor(activeAccount);
    await HomeStripsService.instance.loadFor(activeAccount);
  }

  runApp(const IptvPlayerApp());
}

/// The first screen after the disclaimer. Shows the profile picker when the
/// choice of profile is meaningful — more than one profile exists, or the
/// active one is PIN-protected (so it gates entry) — and otherwise goes
/// straight into the app for the lone profile, adding a playlist first if it
/// has none.
Widget _startupHome() {
  final profiles = ProfilesService.instance;
  final needsPicker = profiles.profiles.length > 1 ||
      (profiles.activeProfile?.hasPin ?? false);
  if (needsPicker) return const ProfilePickerScreen();
  return AccountsService.instance.activeAccount == null
      ? const LoginScreen()
      : const HomeShell();
}

class IptvPlayerApp extends StatelessWidget {
  const IptvPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: SettingsService.instance,
      builder: (context, _) {
        // One seed color drives the whole palette for both brightnesses, so
        // switching the accent preset (or light/dark) rebuilds every screen's
        // colors at once - this AnimatedBuilder listens to SettingsService.
        // The tray menu is native (no BuildContext) — rebuild its labels
        // whenever the language setting changes. No-op when tray mode is off.
        unawaited(TrayService.instance.relocalize(
            SettingsService.instance.appLocale ??
                WidgetsBinding.instance.platformDispatcher.locale));
        final seed = SettingsService.instance.themePreset.seed;
        // null for "System default" - leaves ThemeData on the platform font.
        final fontFamily = SettingsService.instance.fontFamily;
        return MaterialApp(
          title: appName,
          // Locale from the language setting (null = follow the device).
          // Arabic automatically flips the whole app to RTL.
          locale: SettingsService.instance.appLocale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: ThemeData(
            useMaterial3: true,
            fontFamily: fontFamily,
            colorScheme: ColorScheme.fromSeed(
              seedColor: seed,
              brightness: Brightness.light,
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            fontFamily: fontFamily,
            colorScheme: ColorScheme.fromSeed(
              seedColor: seed,
              brightness: Brightness.dark,
            ),
          ),
          themeMode: SettingsService.instance.themeMode,
          home: DisclaimerGate(child: _startupHome()),
        );
      },
    );
  }
}