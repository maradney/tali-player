import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/services/tray_service.dart';

/// The signal the player pauses on when the window goes into the tray.
///
/// Only the signal is testable here. Whether playback actually stops needs a
/// real media_kit player and a real window, so the value of these is that the
/// flag flips at the right moments and settles back - a notifier stuck at true
/// would pause every video opened afterwards, which is the failure that would
/// be hardest to trace back to here.
void main() {
  test('starts visible', () {
    expect(TrayService.instance.hiddenToTray.value, isFalse);
  });

  test('notifies listeners on the way in and out', () async {
    final seen = <bool>[];
    void listener() => seen.add(TrayService.instance.hiddenToTray.value);
    TrayService.instance.hiddenToTray.addListener(listener);
    addTearDown(
        () => TrayService.instance.hiddenToTray.removeListener(listener));

    TrayService.instance.hiddenToTray.value = true;
    TrayService.instance.hiddenToTray.value = false;

    expect(seen, [true, false],
        reason: 'the player needs both edges: one to pause on, and one that '
            'leaves the flag clean for the next time');
  });

  test('a repeated value does not re-notify', () async {
    // Hiding an already-hidden window must not fire again; the player would
    // pause something the viewer had just deliberately resumed.
    TrayService.instance.hiddenToTray.value = true;
    var calls = 0;
    void listener() => calls++;
    TrayService.instance.hiddenToTray.addListener(listener);
    addTearDown(() {
      TrayService.instance.hiddenToTray.removeListener(listener);
      TrayService.instance.hiddenToTray.value = false;
    });

    TrayService.instance.hiddenToTray.value = true;
    expect(calls, 0);
  });
}
