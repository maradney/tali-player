import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/platform_capabilities.dart';

void main() {
  tearDown(() => debugIsDesktopWindowOverride = null);

  test('matches the host platform by default (tests run on desktop)', () {
    final onDesktopHost =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    expect(isDesktopWindow, onDesktopHost);
  });

  test('the test override wins in both directions and resets', () {
    debugIsDesktopWindowOverride = false;
    expect(isDesktopWindow, isFalse, reason: 'simulated mobile');
    debugIsDesktopWindowOverride = true;
    expect(isDesktopWindow, isTrue);
    debugIsDesktopWindowOverride = null;
    expect(isDesktopWindow,
        Platform.isWindows || Platform.isLinux || Platform.isMacOS);
  });
}
