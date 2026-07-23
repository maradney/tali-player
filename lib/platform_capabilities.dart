import 'dart:io';

import 'package:flutter/foundation.dart';

/// Overridable in tests (and only there) so widget tests can exercise both the
/// desktop and mobile shapes of a screen regardless of the host running them.
@visibleForTesting
bool? debugIsDesktopWindowOverride;

/// Whether the app runs inside a desktop OS window that it manages itself —
/// the gate for everything built on window_manager/tray_manager (fullscreen
/// toggle, minimum size, PiP-by-shrinking-the-window, close-to-tray). Those
/// plugins are desktop-only: calling them on Android/iOS throws
/// MissingPluginException, so every such call must sit behind this check.
///
/// Mobile equivalents (SystemChrome immersive mode, native Android PiP) are
/// separate features, not something this flag should quietly stand in for.
bool get isDesktopWindow =>
    debugIsDesktopWindowOverride ??
    (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS));
