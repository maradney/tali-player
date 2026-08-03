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

/// Overridable in tests (and only there), like [debugIsDesktopWindowOverride].
@visibleForTesting
bool? debugSupportsSaveFileDialogOverride;

/// Whether file_selector can show a native "save as" dialog that returns a
/// path we may write to — `getSaveLocation`.
///
/// Only the desktop implementations provide it. file_selector_android exposes
/// just openFile/openFiles/getDirectoryPath, so calling getSaveLocation there
/// throws UnimplementedError rather than failing gracefully; callers must pick
/// a destination another way (see the settings export, which asks for a
/// directory and names the file itself).
///
/// Deliberately a separate flag from [isDesktopWindow] even though it happens
/// to cover the same platforms today: this is about a file-dialog capability,
/// not about owning an OS window, and conflating them would mean a change to
/// either plugin's support silently moved the other.
bool get supportsSaveFileDialog =>
    debugSupportsSaveFileDialogOverride ??
    (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS));
