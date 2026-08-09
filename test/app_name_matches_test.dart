import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app_info.dart';

/// The app's display name lives in three places that cannot import each other:
/// [appName] for everything Dart draws, the Android string resource read by the
/// OS before any Dart runs, and the Windows executable name baked into CMake.
/// Nothing but this test stops them drifting apart at the next rename - which
/// is exactly what happened when the launcher kept saying "IPTV Player" long
/// after the app had been renamed.
void main() {
  String read(String path) {
    final file = File(path);
    expect(file.existsSync(), isTrue, reason: '$path is missing');
    return file.readAsStringSync();
  }

  test('the Android launcher label matches appName', () {
    final xml = read('android/app/src/main/res/values/strings.xml');
    final match =
        RegExp(r'<string name="app_name">([^<]+)</string>').firstMatch(xml);
    expect(match, isNotNull, reason: 'no app_name string resource found');
    expect(match!.group(1)!.trim(), appName);
  });

  test('the manifest points at the string resource rather than a literal', () {
    // A hard-coded label would pass the test above while still being wrong on
    // a device, and would silently lose the Arabic values-ar override.
    final manifest = read('android/app/src/main/AndroidManifest.xml');
    expect(manifest, contains('android:label="@string/app_name"'));
  });

  test('a translated label exists for Arabic', () {
    final xml = read('android/app/src/main/res/values-ar/strings.xml');
    final match =
        RegExp(r'<string name="app_name">([^<]+)</string>').firstMatch(xml);
    expect(match, isNotNull);
    expect(match!.group(1)!.trim(), isNotEmpty);
    expect(match.group(1)!.trim(), isNot(appName),
        reason: 'values-ar should carry the Arabic spelling, not the default');
  });

  test('the Windows binary name matches appSlug', () {
    final cmake = read('windows/CMakeLists.txt');
    expect(cmake, contains('set(BINARY_NAME "$appSlug")'));
    // tool/package_release.ps1 looks the executable up by name; if BINARY_NAME
    // moves without it, packaging fails only at release time.
    expect(read('tool/package_release.ps1'), contains('$appSlug.exe'));
  });
}
