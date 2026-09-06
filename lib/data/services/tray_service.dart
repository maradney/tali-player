import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../../app_info.dart';
import '../../l10n/app_localizations.dart';

/// Windows system-tray integration: an opt-in "keep running in the tray"
/// mode where closing the window hides the app (audio keeps playing — the
/// player is native and doesn't care whether the window is visible) and a
/// tray icon brings it back or exits for real.
///
/// Global (not per-profile): it's a property of the OS window, not of
/// whoever is signed in.
class TrayService extends ChangeNotifier with TrayListener, WindowListener {
  TrayService._();
  static final TrayService instance = TrayService._();

  static const _prefsKey = 'tray_close_to_tray_v1';
  static const _menuShow = 'show';
  static const _menuExit = 'exit';

  bool _closeToTray = false;
  bool get closeToTray => _closeToTray;

  /// The locale the tray menu was last built with — rebuilt when the app
  /// language changes (the menu is native, not a Flutter widget).
  Locale? _menuLocale;

  Future<void> init() async {
    if (!Platform.isWindows) return; // Windows-first, like the tray item says
    final prefs = await SharedPreferences.getInstance();
    _closeToTray = prefs.getBool(_prefsKey) ?? false;
    trayManager.addListener(this);
    windowManager.addListener(this);
    if (_closeToTray) await _enable();
  }

  Future<void> setCloseToTray(bool value, {Locale? locale}) async {
    if (value == _closeToTray) return;
    _closeToTray = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, value);
    if (value) {
      await _enable(locale: locale);
    } else {
      await _disable();
    }
  }

  /// Rebuilds the native menu in [locale]'s language (called from the UI when
  /// the language setting changes; a menu can't listen to a BuildContext).
  Future<void> relocalize(Locale locale) async {
    if (!_closeToTray || locale == _menuLocale) return;
    await _buildMenu(locale);
  }

  Future<void> _enable({Locale? locale}) async {
    await windowManager.setPreventClose(true);
    await trayManager.setIcon('assets/icons/app_icon.ico');
    await _buildMenu(locale ?? PlatformDispatcher.instance.locale);
  }

  Future<void> _disable() async {
    await windowManager.setPreventClose(false);
    await trayManager.destroy();
    _menuLocale = null;
  }

  Future<void> _buildMenu(Locale locale) async {
    final l = _lookup(locale);
    _menuLocale = locale;
    await trayManager.setToolTip(appName);
    await trayManager.setContextMenu(Menu(items: [
      MenuItem(key: _menuShow, label: l.trayShowWindow),
      MenuItem.separator(),
      MenuItem(key: _menuExit, label: l.trayExit),
    ]));
  }

  static AppLocalizations _lookup(Locale locale) {
    try {
      return lookupAppLocalizations(locale);
    } catch (_) {
      return lookupAppLocalizations(const Locale('en'));
    }
  }

  /// True while the window is hidden in the tray rather than closed.
  ///
  /// A ValueNotifier rather than a callback so more than one screen can react
  /// without the tray having to know who they are.
  final ValueNotifier<bool> hiddenToTray = ValueNotifier(false);

  Future<void> _showWindow() async {
    hiddenToTray.value = false;
    await windowManager.show();
    await windowManager.focus();
  }

  /// Really quit. Hide the window first (instant feedback), drop the tray
  /// icon, then hard-exit the process: `windowManager.destroy()` alone can
  /// take seconds, because closing the window still leaves the native player
  /// (mpv), downloads, and timers winding the process down. The user asked to
  /// quit — anything persistent was already awaited when it was written, so
  /// exiting immediately loses nothing.
  Future<void> _exit() async {
    await windowManager.hide();
    await trayManager.destroy();
    exit(0);
  }

  // ---- tray events ----

  @override
  void onTrayIconMouseDown() {
    _showWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case _menuShow:
        _showWindow();
      case _menuExit:
        _exit();
    }
  }

  // ---- window events ----

  @override
  void onWindowClose() async {
    // Only reachable with preventClose on (i.e. tray mode enabled): hide
    // instead of exiting. Downloads and the catalog sync keep running, which
    // is the point of the mode. Video does not: the player watches
    // [hiddenToTray] and pauses, because a hidden window still playing a film
    // is just a soundtrack with no way to see what it belongs to.
    if (_closeToTray) {
      await windowManager.hide();
      hiddenToTray.value = true;
    } else {
      await windowManager.destroy();
    }
  }
}
