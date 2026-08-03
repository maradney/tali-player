import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app_info.dart';
import 'package:iptv_player/features/settings/settings_screen.dart';
import 'package:iptv_player/platform_capabilities.dart';
import 'package:path/path.dart' as p;

/// Where a settings export is written, which differs by platform: desktop gets
/// a native save dialog, Android has none (file_selector_android implements
/// only openFile/openFiles/getDirectoryPath) so we ask for a folder and name
/// the file ourselves. Tested without a file dialog — the naming and the
/// platform decision are the parts that can actually be wrong.
void main() {
  tearDown(() => debugSupportsSaveFileDialogOverride = null);

  group('backupFileName', () {
    test('tracks the app name so a rename renames the file', () {
      expect(backupFileName, '${appSlug}_settings.json');
      expect(backupFileName, endsWith('.json'));
    });

    test('is a bare filename, never a path', () {
      // It gets joined onto a user-chosen directory; a separator here would
      // silently write outside the folder the user picked.
      expect(backupFileName, isNot(contains('/')));
      expect(backupFileName, isNot(contains(r'\')));
    });
  });

  group('backupPathIn', () {
    test('puts the backup inside the chosen directory', () {
      final path = backupPathIn(p.join('some', 'folder'));
      expect(p.basename(path), backupFileName);
      expect(p.dirname(path), p.join('some', 'folder'));
    });

    test('does not double a trailing separator', () {
      final path = backupPathIn('${p.join('some', 'folder')}${p.separator}');
      expect(path, p.join('some', 'folder', backupFileName));
    });
  });

  group('supportsSaveFileDialog', () {
    test('is honoured from the override, both ways', () {
      // The export branches on this; if it were wrong on Android the app would
      // call getSaveLocation there and throw UnimplementedError.
      debugSupportsSaveFileDialogOverride = false;
      expect(supportsSaveFileDialog, isFalse);
      debugSupportsSaveFileDialogOverride = true;
      expect(supportsSaveFileDialog, isTrue);
    });

    test('falls back to the real platform when not overridden', () {
      debugSupportsSaveFileDialogOverride = null;
      // The suite runs on Windows, where the save dialog does exist.
      expect(supportsSaveFileDialog, isTrue);
    });

    test('is independent of isDesktopWindow', () {
      // Same platforms today, but they answer different questions — setting
      // one must not move the other.
      debugSupportsSaveFileDialogOverride = false;
      debugIsDesktopWindowOverride = true;
      expect(isDesktopWindow, isTrue);
      expect(supportsSaveFileDialog, isFalse);
      debugIsDesktopWindowOverride = null;
    });
  });
}
